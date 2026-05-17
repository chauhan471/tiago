defmodule Tiago.Sharing do
  @moduledoc "Sharing context — create and verify shareable ledger links."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Sharing.SharedLedgerLink

  def create_shared_link(attrs) do
    %SharedLedgerLink{}
    |> SharedLedgerLink.changeset(attrs)
    |> Repo.insert()
  end

  def get_active_link_by_token(token) do
    from(l in SharedLedgerLink,
      where: l.token == ^token and l.active == true,
      preload: [:party, :organization]
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      link ->
        if expired?(link), do: nil, else: link
    end
  end

  def list_links_for_org(org_id) do
    from(l in SharedLedgerLink,
      where: l.organization_id == ^org_id,
      order_by: [desc: l.inserted_at],
      preload: [:party, :created_by]
    )
    |> Repo.all()
  end

  def deactivate_link(link_id) do
    case Repo.get(SharedLedgerLink, link_id) do
      nil -> {:error, :not_found}
      link -> link |> Ecto.Changeset.change(active: false) |> Repo.update()
    end
  end

  defp expired?(%SharedLedgerLink{expires_at: nil}), do: false

  defp expired?(%SharedLedgerLink{expires_at: exp}),
    do: DateTime.compare(DateTime.utc_now(), exp) == :gt
end
