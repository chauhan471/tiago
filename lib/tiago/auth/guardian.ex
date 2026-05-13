defmodule Tiago.Auth.Guardian do
  @moduledoc "Guardian implementation for JWT-based authentication."

  use Guardian, otp_app: :tiago

  alias Tiago.Auth

  def subject_for_token(%{id: id}, _claims), do: {:ok, to_string(id)}
  def subject_for_token(_, _), do: {:error, :invalid_resource}

  def resource_from_claims(%{"sub" => id}) do
    case Auth.get_user(id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}
end
