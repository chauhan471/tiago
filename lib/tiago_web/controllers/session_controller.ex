defmodule TiagoWeb.SessionController do
  use TiagoWeb, :controller
  alias Tiago.Auth
  alias Tiago.Auth.Guardian

  def create(conn, %{"_action" => "register", "user" => user_params}) do
    case Auth.register_user(user_params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> Guardian.Plug.sign_in(user)
        |> put_session(:guardian_default_token, token)
        |> put_flash(:info, "Account created! Welcome to Tiago.")
        |> redirect(to: "/organizations")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Registration failed. Please check your details.")
        |> redirect(to: "/register")
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Auth.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> Guardian.Plug.sign_in(user)
        |> put_session(:guardian_default_token, token)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: "/organizations")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: "/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> Guardian.Plug.sign_out()
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/login")
  end
end
