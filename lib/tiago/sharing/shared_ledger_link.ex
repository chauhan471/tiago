defmodule Tiago.Sharing.SharedLedgerLink do
  @moduledoc "Schema for shareable ledger links — read-only access to a party ledger without login."

  use Ecto.Schema
  import Ecto.Changeset

  schema "shared_ledger_links" do
    field :token, :string
    field :label, :string
    field :expires_at, :utc_datetime
    field :active, :boolean, default: true

    belongs_to :party, Tiago.Parties.Party
    belongs_to :organization, Tiago.Organizations.Organization
    belongs_to :created_by, Tiago.Auth.User

    timestamps(type: :utc_datetime)
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:party_id, :organization_id, :created_by_id, :label, :expires_at, :active])
    |> validate_required([:party_id, :organization_id, :created_by_id])
    |> put_token()
    |> unique_constraint(:token)
    |> foreign_key_constraint(:party_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:created_by_id)
  end

  defp put_token(changeset) do
    if get_field(changeset, :token) do
      changeset
    else
      put_change(changeset, :token, generate_token())
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
