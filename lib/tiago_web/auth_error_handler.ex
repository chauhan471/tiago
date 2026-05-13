defmodule TiagoWeb.AuthErrorHandler do
  @moduledoc "Guardian error handler — redirects to login on auth failures."

  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  @behaviour Guardian.Plug.ErrorHandler

  @impl true
  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> put_flash(:error, "Please log in to continue.")
    |> redirect(to: "/login")
  end
end
