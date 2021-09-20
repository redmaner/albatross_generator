defmodule Albagen do
  def create_wallets(number) do
    Task.Supervisor.async_stream_nolink(
      Albagen.Processes.WalletCreatorSupervisor,
      1..number,
      Albagen.Processes.WalletCreator,
      :create,
      [],
      ordered: false,
      timeout: :infinity,
      max_concurrency: Albagen.Config.max_concurrency()
    )
    |> Stream.run()
  end
end
