defmodule Tiago.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :gstn, :string
      timestamps(type: :utc_datetime)
    end

    create table(:org_memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:org_memberships, [:user_id, :organization_id])
    create index(:org_memberships, [:organization_id])
  end
end
