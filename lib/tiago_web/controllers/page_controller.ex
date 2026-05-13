defmodule TiagoWeb.PageController do
  use TiagoWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: "/login")
  end
end
