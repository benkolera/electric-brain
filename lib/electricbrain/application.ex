defmodule Electricbrain.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ElectricbrainWeb.Telemetry,
        Electricbrain.Repo,
        {DNSCluster, query: Application.get_env(:electricbrain, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Electricbrain.PubSub},
        {Registry, keys: :unique, name: Electricbrain.Agenda.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: Electricbrain.Agenda.Supervisor},
        ElectricbrainWeb.Endpoint,
        {AshAuthentication.Supervisor, [otp_app: :electricbrain]},
        Electricbrain.Notifications.Scheduler,
        Electricbrain.Focus.Scheduler,
        Electricbrain.Meals.Scheduler,
        Electricbrain.Training.Scheduler
      ] ++ image_store_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Electricbrain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ElectricbrainWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp image_store_children do
    case Application.get_env(:electricbrain, :notes_image_store_adapter) do
      Electricbrain.Notes.ImageStore.Memory -> [Electricbrain.Notes.ImageStore.Memory]
      nil -> [Electricbrain.Notes.ImageStore.Memory]
      _ -> []
    end
  end
end
