defmodule Albagen.Processes.WalletManager do
  @moduledoc """
  WalletManager makes sure that the wallet to send transactions is imported and unlocked.
  """
  require Logger
  use GenServer

  alias Albagen.Core.Wallet
  alias Albagen.Model.Account
  alias Albagen.Config

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
    Process.sleep(2000)

    Albagen.Config.albatross_nodes()
    |> Enum.each(fn client ->
      case import_and_unlock_wallet(client, address, private_key) do
        :ok ->
          :ok

        :error ->
          raise "Failed to unlock wallet"
      end
    end)

    {:noreply, %{state | unlocked: true, imported: true}, {:continue, :create_wallets}}
  end

  def handle_continue(:create_wallets, state) do
    stakers_to_create = Config.stakers_to_create()

    with {:ok, _result} <- Account.create_table(),
         {:ok, count_stakers} <- Account.count_created_stakers(),
         :ok <- create_new_stakers(count_stakers, stakers_to_create),
         :ok <- load_stakers_from_db() do
      {:noreply, state}
    else
      error ->
        Logger.error("Inspect #{inspect(error)}")
        raise error
    end
  end

  defp import_and_unlock_wallet(client, address, private_key) do
    with {:ok, _result} <- Wallet.ensure_wallet_imported(client, address, private_key),
         {:ok, _result} <- Wallet.ensure_wallet_unlocked(client, address) do
      Logger.info("Imported and unlocked seed address on #{client} -> ready to send transactions")
      :ok
    else
      error ->
        Logger.error("Error when importing and unlocking reward address: #{inspect(error)}")
        :error
    end
  end

  defp create_new_stakers(stakers_created, amount_of_stakers)
       when stakers_created < amount_of_stakers do
    # Stakers are created in concurrent tasks
    stakers_to_create = amount_of_stakers - stakers_created
    concurrent_tasks = get_number_of_tasks()
    task_size = (stakers_to_create / concurrent_tasks) |> round()

    Logger.debug("Creating #{stakers_to_create} stakers with #{concurrent_tasks} tasks")

    (stakers_created + 1)..amount_of_stakers
    |> Stream.chunk_every(task_size)
    |> Enum.each(&create_stakers_with_task/1)

    :ok
  end

  defp create_new_stakers(_stakers_created, _amount_of_stakers), do: :ok

  # We limit the concurrent tasks of creating wallets to 25% of the
  # available schedulers. We do this so that the remaining 75% of the
  # schedulers are available for running the staking processes
  defp get_number_of_tasks do
    System.schedulers_online()
    |> div(4)
    |> round()
    |> max(1)
  end

  defp create_stakers_with_task(stakers_range) do
    Task.Supervisor.async_nolink(
      Albagen.Processes.AccountCreator,
      Albagen.Processes.Staker,
      :create_by_range,
      [stakers_range]
    )
  end

  defp load_stakers_from_db do
    case Account.get_all() do
      {:ok, stakers} ->
        stakers |> Enum.each(&Albagen.Processes.Staker.load/1)

      error ->
        error
    end
  end

  # The task completed successfully
  def handle_info({ref, _answer}, state) do
    # We don't care about the DOWN message now, so let's demonitor and flush it
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info(message, state) do
    Logger.warn("Unhandled message: #{inspect(message)}")
    {:noreply, state}
  end
end
