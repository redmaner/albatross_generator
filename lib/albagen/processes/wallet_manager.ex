defmodule Albagen.Processes.WalletManager do
  @moduledoc """
  WalletManager makes sure that the wallet to send transactions is imported and unlocked.
  """
  require Logger
  use GenServer

  @max_attempts 3
  @attempt_timeout 10_000

  def init(_args) do
    address = Albagen.Config.seed_wallet_addres()
    private_key = Albagen.Config.seed_wallet_key()

    {:ok, %{address: address, private_key: private_key, imported: false, unlocked: false},
     {:continue, :import_and_unlock}}
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: {:global, __MODULE__})
  end

  def handle_continue(:import_and_unlock, state = %{address: address, private_key: private_key}) do
    Logger.info("Albatross generator started: waiting for nodes to be ready")
    Process.sleep(120_000)

    Albagen.Config.albatross_nodes()
    |> Enum.each(fn client ->
      case import_and_unlock_wallet(client, address, private_key, 1) do
        :ok ->
          :ok

        :error ->
          raise "Failed to unlock wallet"
      end
    end)

    {:noreply, %{state | unlocked: true, imported: true}, {:continue, :create_wallets}}
  end

  def handle_continue(:create_wallets, state) do
    Albagen.create_wallets(1000)
    {:noreply, state}
  end

  defp import_and_unlock_wallet(client, address, private_key, attempt) do
    with {:ok, imported_address} <- Albagen.RPC.import_account(client, private_key),
         true <- imported_address == address,
         {:ok, _result} <- Albagen.RPC.unlock_account(client, address) do
      Logger.info("Imported and unlocked seed address on #{client} -> ready to send transactions")
      :ok
    else
      {:error, :timeout} when attempt <= @max_attempts ->
        Process.sleep(attempt * @attempt_timeout)
        import_and_unlock_wallet(client, address, private_key, attempt + 1)

      _ = error ->
        Logger.error("Error when importing and unlocking reward address: #{inspect(error)}")
        :error
    end
  end
end
