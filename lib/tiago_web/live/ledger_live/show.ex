defmodule TiagoWeb.LedgerLive.Show do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Ledger
  import TiagoWeb.Helpers

  def mount(%{"id" => id}, _session, socket) do
    ledger = Ledger.party_ledger(String.to_integer(id))
    {:ok, assign(socket, page_title: "#{ledger.party.name} — Ledger", ledger: ledger, party_id: id, date_from: nil, date_to: nil)}
  end

  def handle_event("filter_dates", %{"date_from" => df, "date_to" => dt}, socket) do
    opts = [] |> add_date(:date_from, df) |> add_date(:date_to, dt)
    ledger = Ledger.party_ledger(String.to_integer(socket.assigns.party_id), opts)
    {:noreply, assign(socket, ledger: ledger, date_from: df, date_to: dt)}
  end

  defp add_date(opts, _, ""), do: opts
  defp add_date(opts, k, v), do: (case Date.from_iso8601(v) do {:ok, d} -> [{k, d} | opts]; _ -> opts end)

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <.link navigate={~p"/parties/#{@party_id}"} class="text-sm text-gray-500 hover:text-gray-700 mb-4 block">← Back</.link>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold"><%= @ledger.party.name %> — Ledger</h1>
          <span class={"px-2 py-1 text-xs rounded-full font-medium #{if @ledger.party.type == :customer, do: "bg-blue-100 text-blue-800", else: "bg-green-100 text-green-800"}"}><%= @ledger.party.type %></span>
        </div>
        <div class="flex gap-2">
          <a href={~p"/parties/#{@party_id}/ledger/csv"} class="bg-gray-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-gray-700">📥 CSV</a>
          <a href={~p"/parties/#{@party_id}/ledger/pdf"} class="bg-red-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-red-700">📄 PDF</a>
        </div>
      </div>
      <form phx-submit="filter_dates" class="flex gap-4 mb-6 items-end">
        <div><label class="block text-xs text-gray-500 mb-1">From</label><input type="date" name="date_from" value={@date_from} class="rounded-lg border-gray-300 text-sm" /></div>
        <div><label class="block text-xs text-gray-500 mb-1">To</label><input type="date" name="date_to" value={@date_to} class="rounded-lg border-gray-300 text-sm" /></div>
        <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700">Filter</button>
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
                <tr class="hover:bg-gray-50">
                  <td class="px-4 py-3 text-sm"><%= fmt_date(e.date) %></td>
                  <td class="px-4 py-3 text-sm"><%= e.description %></td>
                  <td class="px-4 py-3 text-sm text-gray-500"><%= e.reference_number || "—" %></td>
                  <td class="px-4 py-3 text-sm text-right font-mono"><%= if Money.positive?(e.debit), do: fmt_money(e.debit) %></td>
                  <td class="px-4 py-3 text-sm text-right font-mono"><%= if Money.positive?(e.credit), do: fmt_money(e.credit) %></td>
                  <td class="px-4 py-3 text-sm text-right font-mono font-medium"><%= fmt_money(e.balance) %></td>
                </tr>
              <% end %>
            </tbody>
            <tfoot class="bg-gray-100">
              <tr class="font-bold">
                <td colspan="3" class="px-4 py-3 text-sm">Totals</td>
                <td class="px-4 py-3 text-sm text-right font-mono"><%= fmt_money(@ledger.total_debit) %></td>
                <td class="px-4 py-3 text-sm text-right font-mono"><%= fmt_money(@ledger.total_credit) %></td>
                <td class="px-4 py-3 text-sm text-right font-mono"><%= fmt_money(@ledger.closing_balance) %></td>
              </tr>
            </tfoot>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
