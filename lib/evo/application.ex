defmodule Evo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    validate_config!()

    children = [
      EvoWeb.Telemetry,
      Evo.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:evo, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:evo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Evo.PubSub},
      # Evo core services
      Evo.TokenBudget,
      Evo.ModelRouter,
      {Evo.Evolver, auto_start: false},
      # Start to serve requests, typically the last entry
      EvoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Evo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EvoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp validate_config! do
    unless Application.get_env(:evo, :skip_api_key_validation) do
      unless Application.get_env(:evo, :anthropic_api_key) do
        raise """
        ANTHROPIC_API_KEY environment variable is not set.
        Evo requires a valid Anthropic API key to run the evolution loop.
        Export it before starting: export ANTHROPIC_API_KEY=sk-ant-...
        """
      end
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
