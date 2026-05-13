defmodule TiagoWeb.OrgLive.Settings do
  use TiagoWeb, :live_view
  on_mount {TiagoWeb.Live.OrgHook, :default}
  alias Tiago.Organizations

  def mount(_params, _session, socket) do
    members = Organizations.list_members(socket.assigns.current_org.id)
    {:ok, assign(socket, page_title: "Settings", members: members, invite_email: "", invite_role: "accountant")}
  end

  def handle_event("invite", %{"email" => email, "role" => role}, socket) do
    user = Tiago.Auth.get_user_by_email(email)
    org_id = socket.assigns.current_org.id
    cond do
      is_nil(user) -> {:noreply, put_flash(socket, :error, "No user with email: #{email}")}
      Organizations.member?(user.id, org_id) -> {:noreply, put_flash(socket, :error, "Already a member")}
      true ->
        {:ok, _} = Organizations.create_membership(user.id, org_id, String.to_atom(role))
        {:noreply, socket |> put_flash(:info, "#{email} added as #{role}") |> assign(members: Organizations.list_members(org_id))}
    end
  end

  def handle_event("remove", %{"user-id" => uid}, socket) do
    {:ok, _} = Organizations.remove_member(String.to_integer(uid), socket.assigns.current_org.id)
    {:noreply, socket |> put_flash(:info, "Removed") |> assign(members: Organizations.list_members(socket.assigns.current_org.id))}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Organization Settings</h1>
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">Members</h2>
        <table class="min-w-full divide-y divide-gray-200 mb-4">
          <thead><tr>
            <th class="text-left text-xs font-medium text-gray-500 uppercase py-2">Email</th>
            <th class="text-left text-xs font-medium text-gray-500 uppercase py-2">Role</th>
            <th class="text-right text-xs font-medium text-gray-500 uppercase py-2">Actions</th>
          </tr></thead>
          <tbody class="divide-y divide-gray-200">
            <%= for m <- @members do %>
              <tr>
                <td class="py-3 text-sm"><%= m.user.email %></td>
                <td class="py-3 text-sm"><span class={"px-2 py-1 text-xs rounded-full #{if m.role == :admin, do: "bg-purple-100 text-purple-800", else: "bg-blue-100 text-blue-800"}"}><%= m.role %></span></td>
                <td class="py-3 text-sm text-right">
                  <%= if m.role != :admin or length(@members) > 1 do %>
                    <button phx-click="remove" phx-value-user-id={m.user_id} data-confirm="Remove?" class="text-red-600 text-sm">Remove</button>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <h3 class="text-sm font-semibold mb-2">Add Member</h3>
        <form phx-submit="invite" class="flex gap-2">
          <input type="email" name="email" placeholder="Email" required class="flex-1 rounded-lg border-gray-300 text-sm" />
          <select name="role" class="rounded-lg border-gray-300 text-sm"><option value="accountant">Accountant</option><option value="admin">Admin</option></select>
          <button type="submit" class="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium">Add</button>
        </form>
      </div>
    </div>
    """
  end
end
