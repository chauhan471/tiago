defmodule Tiago.Repo.Migrations.CreateBankStatementRows do
  use Ecto.Migration

  def change do
    create table(:bank_statement_rows) do
      add :import_id, references(:bank_statement_imports, on_delete: :delete_all), null: false
      add :raw_data, :map, null: false
      
      add :date, :date
      add :description, :string
      add :reference, :string
      add :debit, :money_with_currency
      add :credit, :money_with_currency
      
      add :party_id, references(:parties, on_delete: :nilify_all)
      add :party_detected, :boolean, default: false
      
      timestamps(type: :utc_datetime)
    end

    create index(:bank_statement_rows, [:import_id])
    create index(:bank_statement_rows, [:party_id])
  end
end
