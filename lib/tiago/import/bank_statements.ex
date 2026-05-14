defmodule Tiago.Import.BankStatements do
  @moduledoc "Context for managing interactive bank statement imports."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Import.{BankStatementImport, BankStatementRow, DateParser}
  alias Tiago.Parties
  alias Tiago.Accounting

  def list_pending_imports(org_id) do
    Repo.all(
      from i in BankStatementImport,
        where: i.organization_id == ^org_id and i.status != "completed",
        order_by: [desc: i.inserted_at]
    )
  end

  def create_import(attrs \\ %{}) do
    %BankStatementImport{}
    |> BankStatementImport.changeset(attrs)
    |> Repo.insert()
  end

  def get_import!(id), do: Repo.get!(BankStatementImport, id)

  def get_import_with_rows!(id) do
    BankStatementImport
    |> preload(rows: ^{:order_by, [asc: :id]})
    |> Repo.get!(id)
  end

  def read_headers_and_sample(filepath) do
    filepath
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Enum.take(3)
    |> case do
      [] -> {:error, "Empty CSV"}
      [first | _] = sample -> {:ok, Map.keys(first), sample}
    end
  end

  def update_import(import, attrs) do
    import
    |> BankStatementImport.changeset(attrs)
    |> Repo.update()
  end

  def update_row(row, attrs) do
    row
    |> BankStatementRow.changeset(attrs)
    |> Repo.update()
  end

  def process_raw_csv(import, filepath, column_mapping) do
    # Ensure any existing rows are deleted if re-processing
    Repo.delete_all(from r in BankStatementRow, where: r.import_id == ^import.id)

    # Cache parties for fast fuzzy matching
    parties = Parties.list_parties(import.organization_id)

    filepath
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Enum.each(fn row ->
      attrs = build_row_attrs(import.id, row, column_mapping, parties)
      %BankStatementRow{} |> BankStatementRow.changeset(attrs) |> Repo.insert!()
    end)

    update_import(import, %{status: "mapped", column_mapping: column_mapping})
  end

  defp build_row_attrs(import_id, raw_row, mapping, parties) do
    date_str = Map.get(raw_row, mapping["date"], "")
    desc = Map.get(raw_row, mapping["description"], "") |> String.trim()
    ref = Map.get(raw_row, mapping["reference"], "") |> String.trim()
    debit_str = Map.get(raw_row, mapping["debit"], "") |> String.trim()
    credit_str = Map.get(raw_row, mapping["credit"], "") |> String.trim()

    date = case DateParser.parse_date(date_str) do
      {:ok, d} -> d
      _ -> nil
    end

    debit = parse_money(debit_str)
    credit = parse_money(credit_str)

    {party_id, detected} = detect_party(desc, ref, parties)

    %{
      import_id: import_id,
      raw_data: raw_row,
      date: date,
      description: desc,
      reference: ref,
      debit: debit,
      credit: credit,
      party_id: party_id,
      party_detected: detected
    }
  end

  defp parse_money(""), do: nil
  defp parse_money("0"), do: nil
  defp parse_money(nil), do: nil
  defp parse_money(str) do
    # Remove commas and attempt to parse
    clean = String.replace(str, ",", "")
    case Float.parse(clean) do
      {f, _} -> Money.new(:INR, f) |> elem(1)
      :error -> nil
    end
  end

  defp detect_party(desc, ref, parties) do
    # Simple substring matching (case-insensitive)
    desc_down = String.downcase(desc)
    ref_down = String.downcase(ref)

    match = Enum.find(parties, fn p ->
      name = String.downcase(p.name)
      String.contains?(desc_down, name) or String.contains?(ref_down, name)
    end)

    if match, do: {match.id, true}, else: {nil, false}
  end

  def create_journals_for_import(import_id) do
    import = get_import_with_rows!(import_id)
    org_id = import.organization_id
    
    bank_account_id = import.bank_account_id || Accounting.get_default_bank_account(org_id).id
    payable = Accounting.get_account_by_sub_type(org_id, :payable)
    receivable = Accounting.get_account_by_sub_type(org_id, :receivable)

    Repo.transaction(fn ->
      Enum.each(import.rows, fn row ->
        # Only process if it has a party and a valid date
        if row.party_id && row.date do
          if row.debit && Money.positive?(row.debit) do
            create_journal(org_id, row.date, row.description, row.reference, :payment, row.party_id,
              [{payable.id, :debit, row.debit}, {bank_account_id, :credit, row.debit}])
          end

          if row.credit && Money.positive?(row.credit) do
            create_journal(org_id, row.date, row.description, row.reference, :payment, row.party_id,
              [{bank_account_id, :debit, row.credit}, {receivable.id, :credit, row.credit}])
          end
        end
      end)

      update_import(import, %{status: "completed"})
    end)
  end

  defp create_journal(org_id, date, desc, ref, transaction_type, party_id, entry_tuples) do
    entries = Enum.map(entry_tuples, fn {acct_id, type, amount} ->
      %{account_id: acct_id, entry_type: type, amount: amount, description: desc, transaction_type: transaction_type, reference_number: ref}
    end)

    Accounting.create_journal(org_id,
      %{date: date, party_id: party_id},
      entries
    )
  end
end
