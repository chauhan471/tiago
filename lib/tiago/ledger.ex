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

    target_sub_type = if party.type == :customer, do: :receivable, else: :payable

    {entries, _} =
      Enum.reduce(journals, {[], Money.new!(:INR, 0)}, fn journal, {acc, balance} ->
        {debit, credit} = compute_debit_credit(journal.entries, target_sub_type)
        new_balance = balance |> Money.add!(debit) |> Money.sub!(credit)
        entry = %{
          date: journal.date, description: journal.description,
          reference_type: journal.reference_type, reference_number: journal.reference_number,
          journal_id: journal.id, debit: debit, credit: credit, balance: new_balance
        }
        {acc ++ [entry], new_balance}
      end)

    %{
      party: party,
      entries: entries,
      total_debit: Enum.reduce(entries, Money.new!(:INR, 0), &Money.add!(&1.debit, &2)),
      total_credit: Enum.reduce(entries, Money.new!(:INR, 0), &Money.add!(&1.credit, &2)),
      closing_balance: if(entries == [], do: Money.new!(:INR, 0), else: List.last(entries).balance)
    }
  end

  defp compute_debit_credit(entries, target_sub_type) do
    Enum.reduce(entries, {Money.new!(:INR, 0), Money.new!(:INR, 0)}, fn entry, {d, c} ->
      account = Tiago.Accounting.get_account!(entry.account_id)
      if account.sub_type == target_sub_type do
        case entry.entry_type do
          :debit -> {Money.add!(d, entry.amount), c}
          :credit -> {d, Money.add!(c, entry.amount)}
        end
      else
        {d, c}
      end
    end)
  end

  defp maybe_filter(q, _, nil), do: q
  defp maybe_filter(q, :date_from, d), do: where(q, [j], j.date >= ^d)
  defp maybe_filter(q, :date_to, d), do: where(q, [j], j.date <= ^d)
end
