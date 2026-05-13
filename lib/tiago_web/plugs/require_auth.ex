defmodule TiagoWeb.Plugs.RequireAuth do
  @moduledoc "Plug that ensures a user is authenticated via Guardian."

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_flash(:error, "Please log in to continue.")
        |> redirect(to: "/login")
        |> halt()

      _user -> conn
    end
  end
end
