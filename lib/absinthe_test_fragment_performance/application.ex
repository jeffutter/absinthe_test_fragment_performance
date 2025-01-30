defmodule AbsintheTestFragmentPerformance.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AbsintheTestFragmentPerformanceWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:absinthe_test_fragment_performance, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AbsintheTestFragmentPerformance.PubSub},
      # Start a worker by calling: AbsintheTestFragmentPerformance.Worker.start_link(arg)
      # {AbsintheTestFragmentPerformance.Worker, arg},
      # Start to serve requests, typically the last entry
      AbsintheTestFragmentPerformanceWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AbsintheTestFragmentPerformance.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AbsintheTestFragmentPerformanceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
