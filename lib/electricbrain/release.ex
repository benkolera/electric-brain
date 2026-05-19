defmodule Electricbrain.Release do
  @moduledoc """
  Release-time tasks. Invoked from the release startup script so a fresh
  container creates the database (if missing) and applies pending migrations
  before the Phoenix endpoint starts. Mix is not available inside an OTP
  release, so we drive Ecto.Migrator directly.
  """

  @app :electricbrain

  def migrate do
    load_app()
    ensure_storage()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # In the bundled poncho deploy, electricbrain shares packheavy's RDS
  # instance as a separate logical database. The database is not provisioned
  # by Pulumi; the app creates it lazily on first boot. Idempotent: returns
  # {:error, :already_up} on subsequent boots, which we treat as success.
  defp ensure_storage do
    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, reason} -> raise "storage_up failed for #{inspect(repo)}: #{inspect(reason)}"
      end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
