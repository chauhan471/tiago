defmodule Tiago.Auth do
  @moduledoc "Authentication context — register, login, user lookup."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Auth.{User, Guardian}

  # ── User CRUD ──

  def get_user(id), do: Repo.get(User, id)

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  # ── Registration ──

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  # ── Login ──

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && User.valid_password?(user, password) ->
        {:ok, user}

      user ->
        {:error, :invalid_password}

      true ->
        Bcrypt.no_user_verify()
        {:error, :user_not_found}
    end
  end

  # ── Guardian Token Helpers ──

  def login(user) do
    Guardian.encode_and_sign(user, %{}, token_type: "access")
  end

  def logout(token) do
    Guardian.revoke(token)
  end

  def current_user(conn_or_socket) do
    Guardian.Plug.current_resource(conn_or_socket)
  end
end
