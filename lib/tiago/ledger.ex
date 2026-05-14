defmodule Tiago.Ledger do
  @moduledoc "Ledger context — org-scoped party-wise ledger generation with running balance."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Accounting.Journal
  alias Tiago.Parties

  def party_ledger(party_id, opts \\ []) do
    party = Parties.get_party!(party_id)

    journals =
      Journal
      |> where([j], j.party_id == ^party_id)
      |> maybe_filter(:date_from, Keyword.get(opts, :date_from))
      |> maybe_filter(:date_to, Keyword.get(opts, :date_to))
      |> order_by([j], asc: j.date, asc: j.id)
      |> preload(:entries)
      |> Repo.all()

    target_sub_types =
      case party.type do
        :customer -> [:receivable]
        :supplier -> [:payable]
        :both_customer_and_supplier -> [:receivable, :payable]
      end

    # Calculate opening balance from entries before the date filter
    opening_balance = compute_opening_balance(party_id, target_sub_types, Keyword.get(opts, :date_from))

    opening_row = %{
      date: Keyword.get(opts, :date_from) || List.first(journals, %{date: Date.utc_today()}) |> Map.get(:date),
      description: "Opening Balance",
      reference_type: nil, reference_number: nil, journal_id: nil,
      debit: Money.new!(:INR, 0), credit: Money.new!(:INR, 0),
      balance: opening_balance,
      is_opening: true
    }

    {entries, _} =
      Enum.reduce(journals, {[], opening_balance}, fn journal, {acc, balance} ->
        {debit, credit} = compute_debit_credit(journal.entries, target_sub_types)
        new_balance = balance |> Money.add!(debit) |> Money.sub!(credit)
        first_entry = List.first(journal.entries) || %{}
        
        entry = %{
          date: journal.date, description: Map.get(first_entry, :description, "—"),
          reference_type: Map.get(first_entry, :transaction_type, "—"), reference_number: Map.get(first_entry, :reference_number, "—"),
          journal_id: journal.id, debit: debit, credit: credit, balance: new_balance,
          is_opening: false
        }
        {acc ++ [entry], new_balance}
      end)

    all_entries = [opening_row | entries]

    %{
      party: party,
      entries: all_entries,
      opening_balance: opening_balance,
      total_debit: Enum.reduce(entries, Money.new!(:INR, 0), &Money.add!(&1.debit, &2)),
      total_credit: Enum.reduce(entries, Money.new!(:INR, 0), &Money.add!(&1.credit, &2)),
      closing_balance: if(entries == [], do: opening_balance, else: List.last(entries).balance)
    }
  end

  defp compute_debit_credit(entries, target_sub_types) do
    Enum.reduce(entries, {Money.new!(:INR, 0), Money.new!(:INR, 0)}, fn entry, {d, c} ->
      account = Tiago.Accounting.get_account!(entry.account_id)
      if account.sub_type in target_sub_types do
        case entry.entry_type do
          :debit -> {Money.add!(d, entry.amount), c}
          :credit -> {d, Money.add!(c, entry.amount)}
        end
      else
        {d, c}
      end
    end)
  end

  # When no date_from filter, opening balance is always 0 (showing full history)
  defp compute_opening_balance(_party_id, _target_sub_types, nil), do: Money.new!(:INR, 0)

  # When date_from filter is set, sum all entries before that date
  defp compute_opening_balance(party_id, target_sub_types, date_from) do
    journals =
      Journal
      |> where([j], j.party_id == ^party_id and j.date < ^date_from)
      |> order_by([j], asc: j.date, asc: j.id)
      |> preload(:entries)
      |> Repo.all()

    Enum.reduce(journals, Money.new!(:INR, 0), fn journal, balance ->
      {debit, credit} = compute_debit_credit(journal.entries, target_sub_types)
      balance |> Money.add!(debit) |> Money.sub!(credit)
    end)
  end

  defp maybe_filter(q, _, nil), do: q
  defp maybe_filter(q, :date_from, d), do: where(q, [j], j.date >= ^d)
  defp maybe_filter(q, :date_to, d), do: where(q, [j], j.date <= ^d)
end
