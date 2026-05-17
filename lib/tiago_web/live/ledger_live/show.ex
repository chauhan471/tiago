defmodule TiagoWeb.LedgerLive.Show do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.{Ledger, Accounting}
  import TiagoWeb.Helpers

  defp invoice_types, do: ~w(sales_invoice purchase_invoice sales_credit_note purchase_credit_note sales_debit_note purchase_debit_note)

  def mount(%{"id" => id}, _session, socket) do
    ledger = Ledger.party_ledger(String.to_integer(id))
    bank_accounts = Accounting.list_bank_accounts(socket.assigns.current_org.id)

    {:ok,
     assign(socket,
       page_title: "#{ledger.party.name} — Ledger",
       ledger: ledger,
       party_id: id,
       date_from: nil,
       date_to: nil,
       show_new_entry: false,
       new_entry_type: "sales_invoice",
       new_entry_error: nil,
       bank_accounts: bank_accounts
     )}
  end

  def handle_event("filter_dates", %{"date_from" => df, "date_to" => dt}, socket) do
    opts = [] |> add_date(:date_from, df) |> add_date(:date_to, dt)
    ledger = Ledger.party_ledger(String.to_integer(socket.assigns.party_id), opts)
    {:noreply, assign(socket, ledger: ledger, date_from: df, date_to: dt)}
  end

  def handle_event("open_new_entry", _, socket) do
    {:noreply, assign(socket, show_new_entry: true, new_entry_error: nil)}
  end

  def handle_event("close_new_entry", _, socket) do
    {:noreply, assign(socket, show_new_entry: false, new_entry_error: nil)}
  end

  def handle_event("change_entry_type", %{"transaction_type" => type}, socket) do
    {:noreply, assign(socket, new_entry_type: type)}
  end

  def handle_event("save_new_entry", params, socket) do
    org_id = socket.assigns.current_org.id
    party_id = String.to_integer(socket.assigns.party_id)

    # For cash types, taxable_amount = total (no GST split needed)
    params =
      if params["transaction_type"] in ["cash_payment_to_supplier", "cash_receipt_from_customer"] do
        Map.put(params, "taxable_amount", params["amount"])
      else
        params
      end

    case Accounting.create_manual_journal(org_id, party_id, params) do
      {:ok, _} ->
        ledger = Ledger.party_ledger(party_id)
        {:noreply,
         socket
         |> assign(ledger: ledger, show_new_entry: false, new_entry_error: nil)
         |> put_flash(:info, "Journal entry created successfully")}

      {:error, reason} when is_binary(reason) ->
        {:noreply, assign(socket, new_entry_error: reason)}

      {:error, changeset} ->
        msg =
          Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end)
          |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
          |> Enum.join("; ")
        {:noreply, assign(socket, new_entry_error: msg)}
    end
  end

  defp add_date(opts, _, ""), do: opts
  defp add_date(opts, k, v) do
    case Date.from_iso8601(v) do
      {:ok, d} -> [{k, d} | opts]
      _ -> opts
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link
        navigate={~p"/parties/#{@party_id}"}
        class="text-sm text-gray-500 hover:text-gray-700 mb-4 block"
      >
        ← Back
      </.link>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold">{@ledger.party.name} — Ledger</h1>
          <span class={"px-2 py-1 text-xs rounded-full font-medium #{party_type_badge_class(@ledger.party.type)}"}>
            {party_type_label(@ledger.party.type)}
          </span>
        </div>
        <div class="flex gap-2">
          <button
            phx-click="open_new_entry"
            class="bg-indigo-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-indigo-700"
          >
            ➕ New Entry
          </button>
          <a
            href={~p"/parties/#{@party_id}/ledger/csv"}
            class="bg-gray-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700"
          >
            📥 CSV
          </a>
          <a
            href={~p"/parties/#{@party_id}/ledger/pdf"}
            class="bg-red-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-red-700"
          >
            📄 PDF
          </a>
        </div>
      </div>

      <%= if @show_new_entry do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
          <div class="bg-white rounded-xl shadow-2xl w-full max-w-lg p-6 relative">
            <button
              phx-click="close_new_entry"
              class="absolute top-4 right-4 text-gray-400 hover:text-gray-600 text-xl font-bold leading-none"
            >
              ×
            </button>
            <h2 class="text-lg font-bold mb-4 text-gray-800">New Journal Entry</h2>

            <%= if @new_entry_error do %>
              <div class="mb-4 bg-red-50 border border-red-200 text-red-700 rounded-lg px-4 py-2 text-sm">
                {@new_entry_error}
              </div>
            <% end %>

            <form phx-submit="save_new_entry" phx-change="change_entry_type" class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1">Transaction Type</label>
                <select
                  name="transaction_type"
                  class="w-full rounded-lg border-gray-300 text-sm"
                >
                  <optgroup label="Sales">
                    <option value="sales_invoice" selected={@new_entry_type == "sales_invoice"}>Sales Invoice</option>
                    <option value="sales_credit_note" selected={@new_entry_type == "sales_credit_note"}>Sales Credit Note</option>
                    <option value="sales_debit_note" selected={@new_entry_type == "sales_debit_note"}>Sales Debit Note</option>
                    <option value="cash_receipt_from_customer" selected={@new_entry_type == "cash_receipt_from_customer"}>Cash Receipt from Customer</option>
                  </optgroup>
                  <optgroup label="Purchases">
                    <option value="purchase_invoice" selected={@new_entry_type == "purchase_invoice"}>Purchase Invoice</option>
                    <option value="purchase_credit_note" selected={@new_entry_type == "purchase_credit_note"}>Purchase Credit Note</option>
                    <option value="purchase_debit_note" selected={@new_entry_type == "purchase_debit_note"}>Purchase Debit Note</option>
                    <option value="cash_payment_to_supplier" selected={@new_entry_type == "cash_payment_to_supplier"}>Cash Payment to Supplier</option>
                  </optgroup>
                </select>
              </div>

              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Date *</label>
                  <input type="date" name="date" required class="w-full rounded-lg border-gray-300 text-sm" />
                </div>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Reference No.</label>
                  <input type="text" name="reference_number" placeholder="e.g. INV-001" class="w-full rounded-lg border-gray-300 text-sm" />
                </div>
              </div>

              <div class={"grid gap-3 #{if @new_entry_type in invoice_types(), do: "grid-cols-2", else: "grid-cols-1"}"}>

                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Total Amount *</label>
                  <input type="text" name="amount" required placeholder="0.00" class="w-full rounded-lg border-gray-300 text-sm font-mono" />
                </div>
                <%= if @new_entry_type in invoice_types() do %>

                  <div>
                    <label class="block text-xs font-medium text-gray-500 mb-1">Taxable Amount *</label>
                    <input type="text" name="taxable_amount" required placeholder="0.00" class="w-full rounded-lg border-gray-300 text-sm font-mono" />
                  </div>
                <% end %>
              </div>

              <%= if @new_entry_type in ["cash_payment_to_supplier", "cash_receipt_from_customer"] do %>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1">Bank / Cash Account *</label>
                  <select name="contra_account_id" required class="w-full rounded-lg border-gray-300 text-sm">
                    <option value="">-- Select Account --</option>
                    <%= for a <- @bank_accounts do %>
                      <option value={a.id}>{a.name}</option>
                    <% end %>
                  </select>
                </div>
              <% end %>

              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1">Description</label>
                <input type="text" name="description" placeholder="Optional note" class="w-full rounded-lg border-gray-300 text-sm" />
              </div>

              <div class="flex justify-end gap-3 pt-2">
                <button type="button" phx-click="close_new_entry" class="text-sm text-gray-600 font-medium hover:text-gray-900 px-4 py-2">
                  Cancel
                </button>
                <button type="submit" class="bg-indigo-600 text-white rounded-lg px-5 py-2 text-sm font-medium hover:bg-indigo-700">
                  Save Entry
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

      <form phx-submit="filter_dates" class="flex gap-4 mb-6 items-end">
        <div>
          <label class="block text-xs text-gray-500 mb-1">From</label>
          <input type="date" name="date_from" value={@date_from} class="rounded-lg border-gray-300 text-sm" />
        </div>
        <div>
          <label class="block text-xs text-gray-500 mb-1">To</label>
          <input type="date" name="date_to" value={@date_to} class="rounded-lg border-gray-300 text-sm" />
        </div>
        <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700">
          Filter
        </button>
      </form>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @ledger.entries == [] do %>
          <div class="px-6 py-12 text-center text-gray-500">No entries found.</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Description</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Ref</th>
                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Debit</th>
                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Credit</th>
                <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Balance</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <%= for e <- @ledger.entries do %>
                <tr class={if e.is_opening, do: "bg-yellow-50 font-medium", else: "hover:bg-gray-50"}>
                  <td class="px-4 py-3 text-sm">{fmt_date(e.date)}</td>
                  <td class={"px-4 py-3 text-sm #{if e.is_opening, do: "italic"}"}>
                    {e.description}
                  </td>
                  <td class="px-4 py-3 text-sm text-gray-500">{e.reference_number || "—"}</td>
                  <td class="px-4 py-3 text-sm text-right font-mono">
                    {if Money.positive?(e.debit), do: fmt_money(e.debit)}
                  </td>
                  <td class="px-4 py-3 text-sm text-right font-mono">
                    {if Money.positive?(e.credit), do: fmt_money(e.credit)}
                  </td>
                  <td class="px-4 py-3 text-sm text-right font-mono font-semibold">
                    {fmt_money(e.balance)}
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot class="bg-gray-100">
              <tr class="font-bold">
                <td colspan="3" class="px-4 py-3 text-sm">Totals</td>
                <td class="px-4 py-3 text-sm text-right font-mono">{fmt_money(@ledger.total_debit)}</td>
                <td class="px-4 py-3 text-sm text-right font-mono">{fmt_money(@ledger.total_credit)}</td>
                <td class="px-4 py-3 text-sm text-right font-mono">{fmt_money(@ledger.closing_balance)}</td>
              </tr>
            </tfoot>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
