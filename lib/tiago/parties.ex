defmodule Tiago.Parties do
  @moduledoc "Parties context — org-scoped party management."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Parties.{Party, PartyGstn}

  def list_parties(org_id, opts \\ []) do
    Party
    |> where([p], p.organization_id == ^org_id)
    |> apply_filters(opts)
    |> order_by([p], asc: p.name)
    |> preload(:party_gstns)
    |> Repo.all()
  end

  defp apply_filters(q, []), do: q
  defp apply_filters(q, [{:type, t} | r]), do: q |> where([p], p.type == ^t) |> apply_filters(r)
  defp apply_filters(q, [{:search, s} | r]), do: q |> where([p], ilike(p.name, ^"%#{s}%")) |> apply_filters(r)
  defp apply_filters(q, [_ | r]), do: apply_filters(q, r)

  def get_party!(id), do: Party |> Repo.get!(id) |> Repo.preload(:party_gstns)

  def create_party(org_id, attrs) do
    %Party{}
    |> Party.changeset(Map.put(attrs, :organization_id, org_id))
    |> Repo.insert()
  end

  def delete_party(%Party{} = party), do: Repo.delete(party)

  def add_gstn_to_party(party_id, gstn) do
    %PartyGstn{}
    |> PartyGstn.changeset(%{party_id: party_id, gstn: gstn})
    |> Repo.insert()
  end

  def find_party_by_gstn(org_id, gstn) do
    from(pg in PartyGstn,
      join: p in assoc(pg, :party),
      where: pg.gstn == ^gstn and p.organization_id == ^org_id,
      select: p,
      preload: :party_gstns
    )
    |> Repo.one()
  end

  def get_or_create_party_by_gstn(org_id, gstn, attrs) do
    case find_party_by_gstn(org_id, gstn) do
      nil ->
        name = Map.get(attrs, :name) || Map.get(attrs, "name", gstn)
        type = Map.get(attrs, :type) || Map.get(attrs, "type", :supplier)

        Repo.transaction(fn ->
          {:ok, party} = create_party(org_id, %{name: name, type: type})
          {:ok, _} = add_gstn_to_party(party.id, gstn)
          Repo.preload(party, :party_gstns)
        end)

      party -> {:ok, party}
    end
  end

  def list_parties_by_name_like(org_id, pattern) do
    from(p in Party,
      where: p.organization_id == ^org_id and ilike(p.name, ^"%#{pattern}%"),
      preload: :party_gstns
    )
    |> Repo.all()
  end
end
