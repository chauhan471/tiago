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
    |> order_by([a], asc: a.id)
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

  def update_account(%Account{} = account, attrs) do
    account
    |> Account.changeset(attrs)
    |> Repo.update()
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
  # ── Manual Journal Entry ──

  def create_manual_journal(org_id, party_id, params) do
    type = params["transaction_type"]
    date_str = params["date"] || ""
    ref = String.trim(params["reference_number"] || "")
    desc = String.trim(params["description"] || "")
    total = parse_manual_money(params["amount"])
    taxable = parse_manual_money(params["taxable_amount"])

    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, total} <- validate_money(total),
         {:ok, taxable} <- validate_money(taxable),
         {:ok, gst} <- safe_money_sub(total, taxable) do
      entries = build_manual_entries(org_id, type, total, taxable, gst, params)

      case entries do
        {:error, reason} ->
          {:error, reason}

        entries when is_list(entries) ->
          create_journal(
            org_id,
            %{date: date, party_id: party_id},
            Enum.map(entries, fn e ->
              Map.merge(e, %{
                description: if(desc == "", do: humanize_type(type), else: desc),
                transaction_type: journal_transaction_type(type),
                reference_number: if(ref == "", do: nil, else: ref)
              })
            end)
          )
      end
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, "Invalid date format"}
    end
  end

  defp build_manual_entries(org_id, type, total, taxable, gst, params) do
    receivable = get_account_by_sub_type(org_id, :receivable)
    payable = get_account_by_sub_type(org_id, :payable)
    sales = get_account_by_sub_type(org_id, :sales)
    purchases = get_account_by_sub_type(org_id, :purchases)
    gst_output = get_account_by_sub_type(org_id, :gst_output)
    gst_input = get_account_by_sub_type(org_id, :gst_input)

    case type do
      "sales_invoice" -> [
        %{account_id: receivable.id, entry_type: :debit,  amount: total},
        %{account_id: sales.id,      entry_type: :credit, amount: taxable},
        %{account_id: gst_output.id, entry_type: :credit, amount: gst}
      ]

      "purchase_invoice" -> [
        %{account_id: purchases.id, entry_type: :debit,  amount: taxable},
        %{account_id: gst_input.id, entry_type: :debit,  amount: gst},
        %{account_id: payable.id,   entry_type: :credit, amount: total}
      ]

      "sales_credit_note" -> [
        %{account_id: sales.id,      entry_type: :debit,  amount: taxable},
        %{account_id: gst_output.id, entry_type: :debit,  amount: gst},
        %{account_id: receivable.id, entry_type: :credit, amount: total}
      ]

      "sales_debit_note" -> [
        %{account_id: receivable.id, entry_type: :debit,  amount: total},
        %{account_id: sales.id,      entry_type: :credit, amount: taxable},
        %{account_id: gst_output.id, entry_type: :credit, amount: gst}
      ]

      "purchase_credit_note" -> [
        %{account_id: payable.id,   entry_type: :debit,  amount: total},
        %{account_id: purchases.id, entry_type: :credit, amount: taxable},
        %{account_id: gst_input.id, entry_type: :credit, amount: gst}
      ]

      "purchase_debit_note" -> [
        %{account_id: purchases.id, entry_type: :debit,  amount: taxable},
        %{account_id: gst_input.id, entry_type: :debit,  amount: gst},
        %{account_id: payable.id,   entry_type: :credit, amount: total}
      ]

      "cash_payment_to_supplier" ->
        contra_id = parse_int(params["contra_account_id"])
        if contra_id do
          [
            %{account_id: payable.id,  entry_type: :debit,  amount: total},
            %{account_id: contra_id,   entry_type: :credit, amount: total}
          ]
        else
          {:error, "Please select a bank/cash account"}
        end

      "cash_receipt_from_customer" ->
        contra_id = parse_int(params["contra_account_id"])
        if contra_id do
          [
            %{account_id: contra_id,      entry_type: :debit,  amount: total},
            %{account_id: receivable.id,  entry_type: :credit, amount: total}
          ]
        else
          {:error, "Please select a bank/cash account"}
        end

      _ ->
        {:error, "Unknown transaction type"}
    end
  end

  defp journal_transaction_type("sales_invoice"),        do: :invoice
  defp journal_transaction_type("purchase_invoice"),     do: :invoice
  defp journal_transaction_type("sales_credit_note"),    do: :credit_note
  defp journal_transaction_type("purchase_credit_note"), do: :credit_note
  defp journal_transaction_type("sales_debit_note"),     do: :debit_note
  defp journal_transaction_type("purchase_debit_note"),  do: :debit_note
  defp journal_transaction_type(_),                      do: :payment

  defp humanize_type("sales_invoice"),        do: "Sales Invoice"
  defp humanize_type("purchase_invoice"),     do: "Purchase Invoice"
  defp humanize_type("sales_credit_note"),    do: "Sales Credit Note"
  defp humanize_type("purchase_credit_note"), do: "Purchase Credit Note"
  defp humanize_type("sales_debit_note"),     do: "Sales Debit Note"
  defp humanize_type("purchase_debit_note"),  do: "Purchase Debit Note"
  defp humanize_type("cash_payment_to_supplier"),     do: "Cash Payment"
  defp humanize_type("cash_receipt_from_customer"),   do: "Cash Receipt"
  defp humanize_type(t),                              do: t

  defp parse_manual_money(nil), do: nil
  defp parse_manual_money(""), do: nil
  defp parse_manual_money(str) when is_binary(str) do
    clean = String.replace(str, ",", "") |> String.trim()
    case Decimal.parse(clean) do
      {d, ""} -> Money.new!(:INR, Decimal.round(d, 2))
      _ -> nil
    end
  end
  defp parse_manual_money(n) when is_number(n), do: Money.new!(:INR, Decimal.new(n))

  defp validate_money(nil), do: {:error, "Amount is required"}
  defp validate_money(%Money{} = m) do
    if Money.positive?(m), do: {:ok, m}, else: {:error, "Amount must be positive"}
  end

  defp safe_money_sub(total, taxable) do
    gst = Money.sub!(total, taxable)
    if Money.negative?(gst),
      do: {:error, "Taxable amount cannot exceed total amount"},
      else: {:ok, gst}
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end
  defp parse_int(n) when is_integer(n), do: n
end
