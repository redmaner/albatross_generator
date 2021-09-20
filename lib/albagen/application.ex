defmodule Albagen.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    http_pools =
      Albagen.Config.albatross_nodes()
      |> Enum.reduce(%{}, fn node, acc ->
        acc |> Map.put(node, size: 8, count: 4)
      end)
      |> Map.put(:default, size: 8, count: 4)

    children = [
      %{
        id: Albagen.Processes.Sqlite,
        start:
          {Sqlitex.Server, :start_link, [Albagen.Config.sqlite_path(), [name: :albagen_sqlite]]}
      },
      {Task.Supervisor, name: Albagen.Processes.WalletCreatorSupervisor, max_children: :infinity},
      Albagen.Processes.SqliteInitializer,
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
