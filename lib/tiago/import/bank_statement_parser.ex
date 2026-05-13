defmodule Tiago.Import.BankStatementParser do
  @moduledoc "Parser for bank statement CSV — org-scoped, with selectable bank account."

  require Logger
  alias Tiago.{Accounting, Parties}
  alias Tiago.Import.DateParser

  @doc """
  Processes a bank statement CSV. `bank_account_id` specifies which bank account to use.
  If nil, uses the default bank account for the org.
  """
  def process_csv(org_id, filepath, bank_account_id \\ nil) do
    bank_account = resolve_bank_account(org_id, bank_account_id)

    results =
      filepath
      |> File.stream!()
      |> Stream.drop(1)
      |> CSV.decode!(headers: true)
      |> Enum.map(&process_row(org_id, bank_account, &1))

    {ok, _errors} = Enum.split_with(results, &(&1 == :skip or match?({:ok, _}, &1)))
    journals = Enum.count(ok, &match?({:ok, _}, &1))
    {:ok, %{rows_processed: length(results), journals_created: journals}}
  end

  defp resolve_bank_account(org_id, nil), do: Accounting.get_default_bank_account(org_id)
  defp resolve_bank_account(_org_id, id), do: Accounting.get_account!(id)

  defp process_row(org_id, bank_account, row) do
    name = get_trimmed(row, "Counterparty")
    credit = get_trimmed(row, "Credit")
    debit = get_trimmed(row, "Debit")
    desc = get_trimmed(row, "Description")
    ref = get_trimmed(row, "Ref No./Cheque No.")
    txn_date = get_trimmed(row, "Txn Date")

    with {:ok, date} <- DateParser.parse_date(txn_date),
         {:ok, party} <- find_party(org_id, name) do
      cond do
        debit != "" and debit != "0" ->
          amount = Money.new!(:INR, debit)
          payable = Accounting.get_account_by_sub_type(org_id, :payable)
          create_journal(org_id, date, desc, ref, :payment, party,
            [{payable.id, :debit, amount}, {bank_account.id, :credit, amount}])

        credit != "" and credit != "0" ->
          amount = Money.new!(:INR, credit)
          receivable = Accounting.get_account_by_sub_type(org_id, :receivable)
          create_journal(org_id, date, desc, ref, :payment, party,
            [{bank_account.id, :debit, amount}, {receivable.id, :credit, amount}])

        true -> :skip
      end
    else
      {:error, :not_found} -> Logger.warning("No party: #{name}"); :skip
      {:error, reason} -> Logger.error("Row error: #{inspect(reason)}"); {:error, reason}
    end
  end

  defp create_journal(org_id, date, desc, ref, ref_type, party, entry_tuples) do
    entries = Enum.map(entry_tuples, fn {acct_id, type, amount} ->
      %{account_id: acct_id, entry_type: type, amount: amount, description: desc}
    end)

    Accounting.create_journal(org_id,
      %{date: date, description: desc, reference_type: ref_type, reference_number: ref, party_id: party.id},
      entries
    )
  end

  defp find_party(_org_id, ""), do: {:error, :not_found}
  defp find_party(org_id, name) do
    case Parties.list_parties_by_name_like(org_id, name) do
      [] -> {:error, :not_found}
      [party | _] -> {:ok, party}
    end
  end

  defp get_trimmed(row, key), do: row |> Map.get(key, "") |> String.trim()
end
