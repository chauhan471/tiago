defmodule Tiago.Parties.Party do
  @moduledoc "Schema for a business party (customer, supplier, or both), scoped to organization."

  use Ecto.Schema
  import Ecto.Changeset

  @party_types [:customer, :supplier, :both_customer_and_supplier]

  schema "parties" do
    field :name, :string
    field :type, Ecto.Enum, values: @party_types
    field :notes, :string

    belongs_to :organization, Tiago.Organizations.Organization
    has_many :party_gstns, Tiago.Parties.PartyGstn
    has_many :journals, Tiago.Accounting.Journal

    timestamps(type: :utc_datetime)
  end

  def changeset(party, attrs) do
    party
    |> cast(attrs, [:name, :type, :notes, :organization_id])
    |> validate_required([:name, :type, :organization_id])
    |> validate_inclusion(:type, @party_types)
    |> foreign_key_constraint(:organization_id)
  end

  def party_types, do: @party_types
end
