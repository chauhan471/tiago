defmodule Tiago.Accounting do
  @moduledoc "Accounting context — org-scoped chart of accounts and double-entry bookkeeping."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Accounting.{Account, Journal, JournalEntry}

  # ── Account CRUD ──

  def list_accounts(org_id, opts \\ []) do
    Account
    |> where([a], a.organization_id == ^org_id)
    |> apply_account_filters(opts)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  defp apply_account_filters(q, []), do: q

  defp apply_account_filters(q, [{:account_type, t} | r]),
    do: q |> where([a], a.account_type == ^t) |> apply_account_filters(r)

  defp apply_account_filters(q, [{:sub_type, s} | r]),
    do: q |> where([a], a.sub_type == ^s) |> apply_account_filters(r)

  defp apply_account_filters(q, [_ | r]), do: apply_account_filters(q, r)

  def get_account!(id), do: Repo.get!(Account, id)

  def get_account_by_sub_type(org_id, sub_type) do
    from(a in Account,
      where: a.organization_id == ^org_id and a.sub_type == ^sub_type,
      order_by: [desc: a.is_default],
      limit: 1
    )
    |> Repo.one()
  end

  def get_default_bank_account(org_id) do
    from(a in Account,
      where: a.organization_id == ^org_id and a.sub_type == :bank,
      order_by: [desc: a.is_default],
      limit: 1
    )
    |> Repo.one()
  end

  def list_bank_accounts(org_id) do
    from(a in Account,
      where: a.organization_id == ^org_id and a.sub_type == :bank,
      order_by: [desc: a.is_default, asc: a.name]
    )
    |> Repo.all()
  end

  def create_account(org_id, attrs) do
    %Account{}
    |> Account.changeset(Map.put(attrs, :organization_id, org_id))
    |> Repo.insert()
  end

  # ── Journal + Entries ──

  def create_journal(org_id, journal_attrs, entries) when is_list(entries) do
    with :ok <- validate_minimum_entries(entries),
         :ok <- validate_balanced(entries) do
      journal_attrs = Map.put(journal_attrs, :organization_id, org_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:journal, Journal.changeset(%Journal{}, journal_attrs))
      |> Ecto.Multi.run(:entries, fn _repo, %{journal: journal} ->
        result =
          Enum.reduce_while(entries, {:ok, []}, fn attrs, {:ok, acc} ->
            attrs =
              attrs
              |> Map.put(:journal_id, journal.id)
              |> Map.put_new(:date, journal.date)

            case %JournalEntry{} |> JournalEntry.changeset(attrs) |> Repo.insert() do
              {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
              {:error, changeset} -> {:halt, {:error, changeset}}
            end
          end)

        case result do
          {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
          {:error, changeset} -> {:error, changeset}
        end
      end)
      |> Ecto.Multi.run(:update_balances, fn _repo, %{entries: entries} ->
        update_account_balances(entries)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{journal: journal}} -> {:ok, Repo.preload(journal, :entries)}
        {:error, _step, changeset, _} -> {:error, changeset}
      end
    end
  end

  def get_journal!(id), do: Journal |> Repo.get!(id) |> Repo.preload(entries: :account)

  def list_journals(org_id, opts \\ []) do
    Journal
    |> where([j], j.organization_id == ^org_id)
    |> apply_journal_filters(opts)
    |> order_by([j], desc: j.date, desc: j.id)
    |> preload([:party, entries: :account])
    |> Repo.all()
  end

  defp apply_journal_filters(q, []), do: q

  defp apply_journal_filters(q, [{:party_id, id} | r]),
    do: q |> where([j], j.party_id == ^id) |> apply_journal_filters(r)

  defp apply_journal_filters(q, [{:date_from, d} | r]),
    do: q |> where([j], j.date >= ^d) |> apply_journal_filters(r)

  defp apply_journal_filters(q, [{:date_to, d} | r]),
    do: q |> where([j], j.date <= ^d) |> apply_journal_filters(r)

  defp apply_journal_filters(q, [_ | r]), do: apply_journal_filters(q, r)

  # ── Setup ──

  def setup_default_accounts(org_id) do
    defaults = [
      %{name: "Bank Account", account_type: :asset, sub_type: :bank, is_default: true},
      %{name: "Accounts Receivable", account_type: :asset, sub_type: :receivable},
      %{name: "GST Input (Receivable)", account_type: :asset, sub_type: :gst_input},
      %{name: "Accounts Payable", account_type: :liability, sub_type: :payable},
      %{name: "GST Output (Payable)", account_type: :liability, sub_type: :gst_output},
      %{name: "Sales Revenue", account_type: :revenue, sub_type: :sales},
      %{name: "Purchases", account_type: :expense, sub_type: :purchases}
    ]

    Enum.map(defaults, fn attrs ->
      case get_account_by_sub_type(org_id, attrs.sub_type) do
        nil -> create_account(org_id, attrs)
        existing -> {:ok, existing}
      end
    end)
  end

  # ── Private ──

  defp validate_minimum_entries(entries) when length(entries) < 2,
    do: {:error, :minimum_two_entries}

  defp validate_minimum_entries(_), do: :ok

  defp validate_balanced(entries) do
    {debits, credits} =
      Enum.reduce(entries, {Money.new!(:INR, 0), Money.new!(:INR, 0)}, fn entry, {d, c} ->
        entry_type = Map.get(entry, :entry_type) || Map.get(entry, "entry_type")
        amount = Map.get(entry, :amount) || Map.get(entry, "amount")

        case entry_type do
          t when t in [:debit, "debit"] -> {Money.add!(d, amount), c}
          t when t in [:credit, "credit"] -> {d, Money.add!(c, amount)}
        end
      end)

    if Money.equal?(debits, credits), do: :ok, else: {:error, :unbalanced_entries}
  end

  defp update_account_balances(entries) do
    entries
    |> Enum.group_by(& &1.account_id)
    |> Enum.each(fn {account_id, acct_entries} ->
      account = get_account!(account_id)

      new_balance =
        Enum.reduce(acct_entries, account.current_balance, fn entry, balance ->
          case entry.entry_type do
            :debit ->
              if account.account_type in [:asset, :expense],
                do: Money.add!(balance, entry.amount),
                else: Money.sub!(balance, entry.amount)

            :credit ->
              if account.account_type in [:liability, :equity, :revenue],
                do: Money.add!(balance, entry.amount),
                else: Money.sub!(balance, entry.amount)
          end
        end)

      account |> Ecto.Changeset.change(current_balance: new_balance) |> Repo.update!()
    end)

    {:ok, :balances_updated}
  end
end
