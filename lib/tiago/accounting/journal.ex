defmodule Tiago.Accounting.Journal do
  @moduledoc "Schema for accounting journals, scoped to organization."

  use Ecto.Schema
  import Ecto.Changeset

  @reference_types [:invoice, :payment, :credit_note, :debit_note, :manual]

  schema "journals" do
    field :date, :date
    field :description, :string
    field :reference_type, Ecto.Enum, values: @reference_types
    field :reference_number, :string

    belongs_to :organization, Tiago.Organizations.Organization
    belongs_to :party, Tiago.Parties.Party
    has_many :entries, Tiago.Accounting.JournalEntry

    timestamps(type: :utc_datetime)
  end

  def changeset(journal, attrs) do
    journal
    |> cast(attrs, [:date, :description, :reference_type, :reference_number, :party_id, :organization_id])
    |> validate_required([:date, :description, :organization_id])
    |> foreign_key_constraint(:party_id)
    |> foreign_key_constraint(:organization_id)
  end

  def reference_types, do: @reference_types
end
