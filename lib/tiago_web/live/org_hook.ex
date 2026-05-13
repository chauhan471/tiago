defmodule TiagoWeb.Live.OrgHook do
  @moduledoc "LiveView on_mount hook that loads current_user, current_org, current_role from session."

  import Phoenix.LiveView
  import Phoenix.Component
  alias Tiago.Organizations

  def on_mount(:default, _params, session, socket) do
    user =
      case session["guardian_default_token"] do
        nil -> nil
        token ->
          case Tiago.Auth.Guardian.resource_from_token(token) do
            {:ok, user, _claims} -> user
            _ -> nil
          end
      end

    org_id = session["current_org_id"]

    cond do
      is_nil(user) ->
        {:halt, redirect(socket, to: "/login")}

      is_nil(org_id) ->
        {:halt, redirect(socket, to: "/organizations")}

      true ->
        case Organizations.get_membership(user.id, org_id) do
          nil ->
            {:halt, redirect(socket, to: "/organizations")}

          membership ->
            org = Organizations.get_organization!(org_id)

            {:cont,
             socket
             |> assign(:current_user, user)
             |> assign(:current_org, org)
             |> assign(:current_role, membership.role)}
        end
    end
  end

  def on_mount(:auth_only, _params, session, socket) do
    user =
      case session["guardian_default_token"] do
        nil -> nil
        token ->
          case Tiago.Auth.Guardian.resource_from_token(token) do
            {:ok, user, _claims} -> user
            _ -> nil
          end
      end

    if user do
      {:cont, assign(socket, :current_user, user)}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end
end
