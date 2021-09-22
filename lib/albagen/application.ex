defmodule Albagen.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  require Logger
  use Application

  @impl true
  def start(_type, _args) do
    schedulers = System.schedulers_online()

    http_pools =
      Albagen.Config.albatross_nodes()
      |> Enum.reduce(%{}, fn node, acc ->
        acc |> Map.put(node, count: schedulers, protocol: :http2)
      end)
      |> Map.put(:default, size: 50, count: schedulers)

    Logger.debug("HTTP pools: #{inspect(http_pools)}")

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Albagen.Processes.StakerSupervisor},
      %{
        id: Albagen.Processes.Sqlite,
        start:
          {Sqlitex.Server, :start_link, [Albagen.Config.sqlite_path(), [name: :albagen_sqlite]]}
      },
      Albagen.Processes.WalletManager,
      %{
        id: Albagen.Processes.RPCClient,
        start: {Jsonrpc, :start_link, [[name: :nimiq, pools: http_pools]]}
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Albagen.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
