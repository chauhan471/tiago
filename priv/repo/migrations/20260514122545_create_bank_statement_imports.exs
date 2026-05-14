defmodule Tiago.Repo.Migrations.CreateBankStatementImports do
  use Ecto.Migration

  def change do
    create table(:bank_statement_imports) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :bank_account_id, references(:accounts, on_delete: :nilify_all)
      add :filename, :string, null: false
      add :status, :string, default: "pending" # pending, mapping, mapped, completed, failed
      add :column_mapping, :map
      
      timestamps(type: :utc_datetime)
    end

    create index(:bank_statement_imports, [:organization_id])
  end
end
