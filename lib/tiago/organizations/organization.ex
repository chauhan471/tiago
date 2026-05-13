defmodule Tiago.Organizations.Organization do
  @moduledoc "Schema for an organization (business/firm)."

  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :gstn, :string

    has_many :org_memberships, Tiago.Organizations.OrgMembership
    has_many :users, through: [:org_memberships, :user]
    has_many :accounts, Tiago.Accounting.Account
    has_many :parties, Tiago.Parties.Party
    has_many :journals, Tiago.Accounting.Journal

    timestamps(type: :utc_datetime)
  end

  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :gstn])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
