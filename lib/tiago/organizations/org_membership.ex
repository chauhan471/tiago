defmodule Tiago.Organizations.OrgMembership do
  @moduledoc "Schema linking users to organizations with roles."

  use Ecto.Schema
  import Ecto.Changeset

  @roles [:admin, :accountant]

  schema "org_memberships" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :user, Tiago.Auth.User
    belongs_to :organization, Tiago.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :organization_id, :role])
    |> validate_required([:user_id, :organization_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end

  def roles, do: @roles
end
