defmodule Tiago.Import.BankStatements do
  @moduledoc "Context for managing bank statements directly attached to accounts."

  require Logger
  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Import.{BankStatement, DateParser, BankStatementParsers}
  alias Tiago.Parties
  alias Tiago.Accounting

  def list_statements(account_id, opts \\ []) do
    query = from s in BankStatement, where: s.account_id == ^account_id

    query =
      case Keyword.get(opts, :status) do
        "processed" -> where(query, [s], s.is_processed == true)
        "unprocessed" -> where(query, [s], s.is_processed == false)
        _ -> query
      end

    query
    |> order_by([s], asc: s.id)
    |> Repo.all()
  end

  def get_statement!(id), do: Repo.get!(BankStatement, id)

  def update_statement(statement, attrs) do
    statement
    |> BankStatement.changeset(attrs)
    |> Repo.update()
  end

  def delete_statement(statement) do
    Repo.delete(statement)
  end

  def delete_statements(ids) when is_list(ids) do
    Repo.delete_all(from s in BankStatement, where: s.id in ^ids)
  end

  def process_file(account_id, org_id, filepath, format) do
    # Ensure account exists
    _account = Accounting.get_account!(account_id)

    # Cache recent parties for fast fuzzy matching
    parties = Parties.list_parties(org_id) |> Enum.take(50)

    mapping = BankStatementParsers.default_mapping(format)

    inserted =
      filepath
      |> BankStatementParsers.stream_rows(format)
      |> Enum.reduce(0, fn row, acc ->
        attrs = build_statement_attrs(account_id, row, mapping, parties)

        # Skip junk rows (empty lines, footer text) — they won't have a valid date
        if is_nil(attrs[:date]) do
          Logger.warning(
            "[BankStatements] Skipping junk row with no valid date. Raw data: #{inspect(row)}"
          )

          acc
        else
          %BankStatement{} |> BankStatement.changeset(attrs) |> Repo.insert!()
          acc + 1
        end
      end)

    {:ok, %{rows_inserted: inserted}}
  end

  defp build_statement_attrs(account_id, raw_row, mapping, parties) do
    # Create a new map with trimmed keys for reliable lookups
    clean_row = Map.new(raw_row, fn {k, v} -> {String.trim(to_string(k)), v} end)

    date_str = get_and_trim(clean_row, mapping["date"])
    desc = get_and_trim(clean_row, mapping["description"])
    ref = get_and_trim(clean_row, mapping["reference"])
    debit_str = get_and_trim(clean_row, mapping["debit"])
    credit_str = get_and_trim(clean_row, mapping["credit"])

    date =
      case DateParser.parse_date(date_str) do
        {:ok, d} -> d
        _ -> nil
      end

    debit = parse_money(debit_str)
    credit = parse_money(credit_str)

    party_id = detect_party(desc, ref, parties)

    %{
      account_id: account_id,
      raw_data: raw_row,
      date: date,
      description: desc,
      payment_reference: ref,
      debit: debit,
      credit: credit,
      party_id: party_id,
      is_processed: false
    }
  end

  defp get_and_trim(row, key) do
    case Map.get(row, key) do
      nil -> ""
      val when is_binary(val) -> String.trim(val)
      val -> to_string(val) |> String.trim()
    end
  end

  defp parse_money(""), do: nil
  defp parse_money(nil), do: nil

  defp parse_money(str) when is_binary(str) do
    clean = String.replace(str, ",", "") |> String.trim()

    case Float.parse(clean) do
      {f, _} ->
        if f == 0.0 do
          nil
        else
          Money.new!(:INR, Decimal.from_float(f) |> Decimal.round(2))
        end

      :error ->
        nil
    end
  end

  defp parse_money(_), do: nil

  defp detect_party(desc, ref, parties) do
    desc_down = String.downcase(desc || "")
    ref_down = String.downcase(ref || "")
    combined = desc_down <> " " <> ref_down

    # Tokenize the combined text into whole words for accurate word-boundary matching
    combined_words = MapSet.new(Regex.scan(~r/[a-z0-9]+/, combined) |> List.flatten())

    # Sort by length desc so we match longer, more specific names first
    parties = Enum.sort_by(parties, &String.length(&1.name), :desc)

    match =
      Enum.find(parties, fn p ->
        name_down = String.downcase(p.name)

        # 1. Try exact full name match first
        if String.contains?(combined, name_down) do
          true
        else
          # 2. Extract significant words (> 3 chars), split on common separators
          significant_words =
            name_down
            |> String.split([" ", "&", "-", ".", ",", "/"])
            |> Enum.map(&String.trim/1)
            |> Enum.filter(&(String.length(&1) > 3))

          case length(significant_words) do
            0 ->
              false

            1 ->
              # Single significant word: require whole-word match to avoid false positives
              MapSet.member?(combined_words, hd(significant_words))

            n ->
              # Multiple words: require at least 2 matching (or >50% for short names)
              min_matches = max(2, ceil(n * 0.5))
              matched = Enum.count(significant_words, &MapSet.member?(combined_words, &1))
              matched >= min_matches
          end
        end
      end)

    if match, do: match.id, else: nil
  end

  def process_statement_to_ledger(statement_id, org_id) do
    statement = get_statement!(statement_id)

    if statement.is_processed do
      {:error, "Already processed"}
    else
      if !statement.party_id && !statement.counter_account_id do
        {:error, "Counterparty mapping is required"}
      else
        if !statement.date do
          {:error, "Date is required"}
        else
          # Create journal
          result =
            Repo.transaction(fn ->
              if statement.party_id do
                payable = Accounting.get_account_by_sub_type(org_id, :payable)
                receivable = Accounting.get_account_by_sub_type(org_id, :receivable)

                if statement.debit && Money.positive?(statement.debit) do
                  create_journal(
                    org_id,
                    statement.date,
                    statement.description,
                    statement.payment_reference,
                    :payment,
                    statement.party_id,
                    [
                      {payable.id, :debit, statement.debit},
                      {statement.account_id, :credit, statement.debit}
                    ]
                  )
                end

                if statement.credit && Money.positive?(statement.credit) do
                  create_journal(
                    org_id,
                    statement.date,
                    statement.description,
                    statement.payment_reference,
                    :payment,
                    statement.party_id,
                    [
                      {statement.account_id, :debit, statement.credit},
                      {receivable.id, :credit, statement.credit}
                    ]
                  )
                end
              else
                # Map directly to internal account
                counter_id = statement.counter_account_id

                if statement.debit && Money.positive?(statement.debit) do
                  create_journal(
                    org_id,
                    statement.date,
                    statement.description,
                    statement.payment_reference,
                    :payment,
                    nil,
                    [
                      {counter_id, :debit, statement.debit},
                      {statement.account_id, :credit, statement.debit}
                    ]
                  )
                end

                if statement.credit && Money.positive?(statement.credit) do
                  create_journal(
                    org_id,
                    statement.date,
                    statement.description,
                    statement.payment_reference,
                    :payment,
                    nil,
                    [
                      {statement.account_id, :debit, statement.credit},
                      {counter_id, :credit, statement.credit}
                    ]
                  )
                end
              end

              update_statement(statement, %{is_processed: true})
            end)

          case result do
            {:ok, {:ok, _}} -> {:ok, statement}
            {:error, reason} -> {:error, reason}
          end
        end
      end
    end
  end

  defp create_journal(org_id, date, desc, ref, transaction_type, party_id, entry_tuples) do
    entries =
      Enum.map(entry_tuples, fn {acct_id, type, amount} ->
        %{
          account_id: acct_id,
          entry_type: type,
          amount: amount,
          description: desc,
          transaction_type: transaction_type,
          reference_number: ref
        }
      end)

    case Accounting.create_journal(
           org_id,
           %{date: date, party_id: party_id},
           entries
         ) do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
