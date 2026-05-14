defmodule Tiago.Import.BankStatementRow do
  @moduledoc "Schema for a single row in a bank statement import."

  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_statement_rows" do
    field :raw_data, :map
    
    field :date, :date
    field :description, :string
    field :reference, :string
    field :debit, Money.Ecto.Composite.Type
    field :credit, Money.Ecto.Composite.Type
    
    field :party_detected, :boolean, default: false

    belongs_to :import, Tiago.Import.BankStatementImport
    belongs_to :party, Tiago.Parties.Party

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :import_id, :raw_data, :date, :description, :reference,
      :debit, :credit, :party_id, :party_detected
    ])
    |> validate_required([:import_id, :raw_data])
    |> foreign_key_constraint(:import_id)
    |> foreign_key_constraint(:party_id)
  end
end
