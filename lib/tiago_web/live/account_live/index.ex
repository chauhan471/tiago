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
       accounts: Accounting.list_accounts(org_id),
       editing_account_id: nil
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_account_id: String.to_integer(id))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_account_id: nil)}
  end

  def handle_event("save", %{"account_id" => id, "name" => name}, socket) do
    org_id = socket.assigns.current_org.id
    account = Enum.find(socket.assigns.accounts, &(to_string(&1.id) == id))
    
    if account do
      case Accounting.update_account(account, %{name: name}) do
        {:ok, _updated} ->
          {:noreply,
           socket
           |> assign(accounts: Accounting.list_accounts(org_id), editing_account_id: nil)
           |> put_flash(:info, "Account renamed successfully")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to rename account")}
      end
    else
      {:noreply, socket}
    end
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
                    <%= if @editing_account_id == account.id do %>
                      <form phx-submit="save" class="flex gap-2 items-center">
                        <input type="hidden" name="account_id" value={account.id} />
                        <input type="text" name="name" value={account.name} class="rounded border-gray-300 text-sm py-1" required autofocus />
                        <button type="submit" class="text-blue-600 hover:text-blue-800"><heroicon-check class="w-5 h-5"/></button>
                        <button type="button" phx-click="cancel_edit" class="text-gray-500 hover:text-gray-700"><heroicon-x-mark class="w-5 h-5"/></button>
                      </form>
                    <% else %>
                      <div class="flex items-center gap-2 group">
                        {account.name}
                        <button phx-click="edit" phx-value-id={account.id} class="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-blue-600">
                          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                            <path d="M2.695 14.763l-1.262 3.152a.5.5 0 00.65.65l3.152-1.262a4 4 0 001.343-.885L17.5 5.5a2.121 2.121 0 00-3-3L3.58 13.42a4 4 0 00-.885 1.343z" />
                          </svg>
                        </button>
                        <%= if account.is_default do %>
                          <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                            System
                          </span>
                        <% end %>
                      </div>
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
