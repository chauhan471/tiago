defmodule TiagoWeb.OrgController do
  use TiagoWeb, :controller

  def select(conn, %{"org_id" => org_id}) do
    user = Guardian.Plug.current_resource(conn)

    if Tiago.Organizations.member?(user.id, String.to_integer(org_id)) do
      conn
      |> put_session(:current_org_id, String.to_integer(org_id))
      |> redirect(to: "/dashboard")
    else
      conn
      |> put_flash(:error, "You don't have access to that organization.")
      |> redirect(to: "/organizations")
    end
  end
end
