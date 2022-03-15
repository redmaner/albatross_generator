defmodule Albagen.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  require Logger
  use Application

  @impl true
  def start(_type, _args) do
    Albagen.Config.show_config()

    schedulers = System.schedulers_online()

    nimiqex_opts = [
      name: :albagen_rpc_client,
      protocol: :http2,
      pool_count: schedulers,
      pool_timeout: 15_000,
      receive_timeout: 15_000,
      url: Albagen.Config.albatross_nodes()
    ]

    children = [
      Albagen.Processes.Observer,
      {Task.Supervisor, name: Albagen.Processes.AccountCreator},
      {DynamicSupervisor, strategy: :one_for_one, name: Albagen.Processes.StakerSupervisor},
      Albagen.Model.Account,
      Albagen.Processes.WalletManager,
      {Nimiqex, nimiqex_opts}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Albagen.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
