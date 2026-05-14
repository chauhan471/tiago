defmodule Tiago.Import.BankStatementImport do
  @moduledoc "Schema for tracking a bank statement import process."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["pending", "mapping", "mapped", "completed", "failed"]

  schema "bank_statement_imports" do
    field :filename, :string
    field :status, :string, default: "pending"
    field :column_mapping, :map, default: %{}

    belongs_to :organization, Tiago.Organizations.Organization
    belongs_to :bank_account, Tiago.Accounting.Account
    has_many :rows, Tiago.Import.BankStatementRow, foreign_key: :import_id

    timestamps(type: :utc_datetime)
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, [:organization_id, :bank_account_id, :filename, :status, :column_mapping])
    |> validate_required([:organization_id, :filename, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:bank_account_id)
  end
end
