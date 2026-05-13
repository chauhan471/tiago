defmodule TiagoWeb.Plugs.RequireOrg do
  @moduledoc "Plug that loads current organization from session and verifies membership."

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  alias Tiago.Organizations

  def init(opts), do: opts

  def call(conn, _opts) do
    user = Guardian.Plug.current_resource(conn)
    org_id = get_session(conn, :current_org_id)

    cond do
      is_nil(user) ->
        conn |> redirect(to: "/login") |> halt()

      is_nil(org_id) ->
        conn |> redirect(to: "/organizations") |> halt()

      true ->
        case Organizations.get_membership(user.id, org_id) do
          nil ->
            conn
            |> delete_session(:current_org_id)
            |> put_flash(:error, "You don't have access to that organization.")
            |> redirect(to: "/organizations")
            |> halt()

          membership ->
            org = Organizations.get_organization!(org_id)

            conn
            |> assign(:current_org, org)
            |> assign(:current_membership, membership)
            |> assign(:current_role, membership.role)
        end
    end
  end
end
