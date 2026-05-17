defmodule TiagoWeb.SharedLedgerLive do
  use TiagoWeb, :live_view
  alias Tiago.{Sharing, Ledger}
  import TiagoWeb.Helpers

  def mount(%{"token" => token}, _session, socket) do
    case Sharing.get_active_link_by_token(token) do
      nil ->
        {:ok,
         socket |> assign(page_title: "Link Not Found", error: true, ledger: nil, org_name: nil)}

      link ->
        ledger = Ledger.party_ledger(link.party_id)

        {:ok,
         assign(socket,
           page_title: "#{ledger.party.name} — Shared Ledger",
           error: false,
           ledger: ledger,
           org_name: link.organization.name,
           token: token
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <%= if @error do %>
        <div class="text-center py-20">
          <h1 class="text-2xl font-bold text-gray-900 mb-2">Link Not Found</h1>
          <p class="text-gray-500">
            This shared ledger link is invalid, expired, or has been deactivated.
          </p>
        </div>
      <% else %>
        <div class="bg-blue-50 border border-blue-200 rounded-lg px-4 py-3 mb-6 text-sm text-blue-800">
          Shared by <strong>{@org_name}</strong> — Read-only view
        </div>
        <h1 class="text-2xl font-bold mb-4">{@ledger.party.name} — Ledger</h1>
        <div class="bg-white shadow rounded-lg overflow-hidden">
          <%= if @ledger.entries == [] do %>
            <div class="px-6 py-12 text-center text-gray-500">No entries.</div>
          <% else %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Date
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Description
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Debit
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Credit
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Balance
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for e <- @ledger.entries do %>
                  <tr>
                    <td class="px-4 py-3 text-sm">{fmt_date(e.date)}</td>
                    <td class="px-4 py-3 text-sm">{e.description}</td>
                    <td class="px-4 py-3 text-sm text-right font-mono">
                      {if Money.positive?(e.debit), do: fmt_money(e.debit)}
                    </td>
                    <td class="px-4 py-3 text-sm text-right font-mono">
                      {if Money.positive?(e.credit), do: fmt_money(e.credit)}
                    </td>
                    <td class="px-4 py-3 text-sm text-right font-mono font-medium">
                      {fmt_money(e.balance)}
                    </td>
                  </tr>
                <% end %>
              </tbody>
              <tfoot class="bg-gray-100">
                <tr class="font-bold">
                  <td colspan="2" class="px-4 py-3 text-sm">Totals</td>
                  <td class="px-4 py-3 text-sm text-right font-mono">
                    {fmt_money(@ledger.total_debit)}
                  </td>
                  <td class="px-4 py-3 text-sm text-right font-mono">
                    {fmt_money(@ledger.total_credit)}
                  </td>
                  <td class="px-4 py-3 text-sm text-right font-mono">
                    {fmt_money(@ledger.closing_balance)}
                  </td>
                </tr>
              </tfoot>
            </table>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
