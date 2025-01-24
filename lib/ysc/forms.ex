defmodule Ysc.Forms do
  import Ecto.Query, warn: false
  alias Ysc.Repo

  def create_volunteer(changeset) do
    case Repo.insert(changeset) do
      {:ok, volunteer} ->
        {:ok, volunteer}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_conduct_violation_report(changeset) do
    case Repo.insert(changeset) do
      {:ok, report} ->
        {:ok, report}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
