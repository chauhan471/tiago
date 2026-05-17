defmodule Tiago.Organizations do
  @moduledoc "Organizations context — CRUD, membership, role management."

  import Ecto.Query, warn: false
  alias Tiago.Repo
  alias Tiago.Organizations.{Organization, OrgMembership}

  # ── Organization CRUD ──

  def list_user_organizations(user_id) do
    from(o in Organization,
      join: m in OrgMembership,
      on: m.organization_id == o.id,
      where: m.user_id == ^user_id,
      select: %{organization: o, role: m.role},
      order_by: o.name
    )
    |> Repo.all()
  end

  def get_organization!(id), do: Repo.get!(Organization, id)

  def create_organization(attrs, creator_user_id) do
    Repo.transaction(fn ->
      with {:ok, org} <- %Organization{} |> Organization.changeset(attrs) |> Repo.insert(),
           {:ok, _membership} <- create_membership(creator_user_id, org.id, :admin) do
        
        # Automatically set up the default internal ledger accounts (bank, sales, purchases, etc.)
        Tiago.Accounting.setup_default_accounts(org.id)
        
        org
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def update_organization(%Organization{} = org, attrs) do
    org |> Organization.changeset(attrs) |> Repo.update()
  end

  # ── Membership ──

  def create_membership(user_id, org_id, role) do
    %OrgMembership{}
    |> OrgMembership.changeset(%{user_id: user_id, organization_id: org_id, role: role})
    |> Repo.insert()
  end

  def get_membership(user_id, org_id) do
    Repo.get_by(OrgMembership, user_id: user_id, organization_id: org_id)
  end

  def get_user_role(user_id, org_id) do
    case get_membership(user_id, org_id) do
      nil -> nil
      membership -> membership.role
    end
  end

  def list_members(org_id) do
    from(m in OrgMembership,
      where: m.organization_id == ^org_id,
      join: u in assoc(m, :user),
      preload: [user: u],
      order_by: u.email
    )
    |> Repo.all()
  end

  def remove_member(user_id, org_id) do
    case get_membership(user_id, org_id) do
      nil -> {:error, :not_found}
      membership -> Repo.delete(membership)
    end
  end

  def admin?(%OrgMembership{role: :admin}), do: true
  def admin?(_), do: false

  def member?(user_id, org_id) do
    get_membership(user_id, org_id) != nil
  end
end
