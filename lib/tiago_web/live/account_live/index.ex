defmodule TiagoWeb.AccountLive.Index do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Accounting
  import TiagoWeb.Helpers

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_org.id

    {:ok,
     assign(socket,
       page_title: "Accounts",
       accounts: Accounting.list_accounts(org_id)
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-3xl font-bold">Accounts</h1>
      </div>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @accounts == [] do %>
          <div class="px-6 py-12 text-center text-gray-500">No accounts found.</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Sub-Type
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                  Current Balance
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200" id="accounts-list">
              <%= for account <- @accounts do %>
                <tr id={"account-#{account.id}"} class="hover:bg-gray-50">
                  <td class="px-6 py-4 text-sm font-medium text-gray-900">
                    {account.name}
                    <%= if account.is_default do %>
                      <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                        System
                      </span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-500">
                    {Phoenix.Naming.humanize(account.account_type)}
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-500">
                    {if account.sub_type, do: Phoenix.Naming.humanize(account.sub_type), else: "—"}
                  </td>
                  <td class="px-6 py-4 text-sm text-right font-mono font-medium">
                    {fmt_money(account.current_balance)}
                  </td>
                  <td class="px-6 py-4 text-sm text-right space-x-2">
                    <.link
                      navigate={~p"/accounts/#{account.id}/ledger"}
                      class="text-green-600 hover:text-green-800 font-medium"
                    >
                      Ledger
                    </.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
