defmodule Albagen.Processes.Staker do
  require Logger
  use GenServer

  alias Albagen.Core.Wallet
  alias Albagen.Model.Account
  alias Albagen.RPC

  @epoch_time_avg :timer.minutes(3)
  @nim_in_luna 100_000

  @doc """
  create a new staker from scratch and start a staker process once completed
  """
  def create(seed_number) do
    client = Albagen.Config.albatross_nodes() |> Enum.random()

    with {:ok, wallet} <- Albagen.RPC.create_account(client),
         {:ok, account} <- Albagen.Model.Account.parse_from_json(wallet, client, seed_number),
         {:ok, _result} <- Account.insert(account) do
      Logger.info("Created account", address: account.address, seed: seed_number)
      :ok
    else
      {:error, call, reason} ->
        Logger.error("Encountered error for call #{call}: #{inspect(reason)}")

      {:error, reason} ->
        Logger.error("Encountered error: #{inspect(reason)}")
    end
  end

  def load(account) do
    case GenServer.whereis({:global, {__MODULE__, account.address}}) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        {__MODULE__, account}
        |> start_staker()
    end
  end

  defp start_staker(child_spec) do
    case DynamicSupervisor.start_child(Albagen.Processes.StakerSupervisor, child_spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      _ = error ->
        {:error, "#{inspect(error)}"}
    end
  end

  def start_link(account = %Account{address: address}) do
    GenServer.start_link(__MODULE__, account, name: {:global, {__MODULE__, address}})
  end

  def init(account) do
    Logger.metadata(address: account.address)
    Logger.metadata(seed: account.seed_number)
    Logger.info("Process started")

    # If an account is not seeded yet (see seed_account) we spread
    # the processes over an hour. This is to prevent spiking nodes with heavy
    # load since seeding an account is a rather expensive operation especially
    # when doing it for multiple accounts at once
    timer =
      if account.is_seeded == 0 do
        Process.send_after(self(), :seed_account, initial_timer(account.seed_number))
      else
        Process.send_after(
          self(),
          :send_transaction,
          initial_timer(account.seed_number, :timer.seconds(30))
        )
      end

    state = %{
      account: account,
      timer: timer
    }

    {:ok, state}
  end

  # This seeds an account:
  # 1) It imports the account on the node
  # 2) Receives an initial balance from the seed address
  def handle_info(
        :seed_account,
        state = %{account: %Account{private_key: private_key, address: address, node: node}}
      ) do
    balance = Enum.random(1..1000) * @nim_in_luna

    with {:ok, _result} <- Wallet.ensure_wallet_imported(node, address, private_key),
         {:ok, _} <- Albagen.RPC.send_basic_transaction(node, address, balance),
         :ok <- Wallet.wait_for_balance(node, address),
         {:ok, _result} <- Account.set_seeded(address) do
      Logger.info("Account has been imported and received initial balance #{balance}")

      {:noreply,
       %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
    else
      {:error, method, reason} ->
        Logger.error("Seeding account failed during #{method}: #{inspect(reason)}")

        # TODO: check the method and maybe retry
        {:stop, :seeding_failed, state}

      {:error, reason} ->
        # TODO: A database error doesn't necessarily mean the seeding failed
        Logger.error("Seeding account failed: #{inspect(reason)}")
        {:stop, :seeding_failed, state}
    end
  end

  def handle_info(
        :send_transaction,
        state = %{account: %Account{address: address, node: host, private_key: private_key}}
      ) do
    with {:ok, _result} <- Wallet.ensure_wallet_imported(host, address, private_key),
         {:ok, _result} <- Wallet.ensure_wallet_unlocked(host, address),
         {:ok, staker} <- RPC.get_staker(host, address) do
      Logger.debug("Staker: #{inspect(staker)}")
      {:noreply, state}
    else
      {:error, :no_staker_found} ->
        state |> do_new_staker_transaction()

      {:error, method, reason} ->
        Logger.error(
          "Encountered error during transaction setup: #{method} --> #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  defp do_new_staker_transaction(state = %{account: %Account{address: address, node: node}}) do
    with {:ok, balance} <- Wallet.get_balance(node, address),
         validator <- select_active_validator(node),
         stake_percentage <- 1..100 |> Enum.random(),
         stake_balance <- (balance * stake_percentage / 100) |> floor(),
         {:ok, _result} <-
           RPC.send_new_staker_transaction(node, address, validator, stake_balance) do
      Logger.info("Started staking with #{stake_balance} to validator #{validator}")

      {:noreply,
       %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
    else
      {:error, method, reason} ->
        Logger.error(
          "Encountered error when creating new staker: #{method} --> #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  def select_active_validator(host) do
    case Albagen.RPC.list_stakes(host) do
      {:ok, validators} when is_map(validators) and validators != %{} ->
        validators
        |> Enum.random()
        |> extract_validator()

      error ->
        {:error, error}
    end
  end

  defp extract_validator({delegation, _balance}), do: delegation

  defp extract_validator(_), do: raise("No validator found")

  def initial_timer(seed_number, time \\ :timer.seconds(60)) do
    seed_number
    |> rem(60)
    |> Kernel.+(1)
    |> Kernel.*(time)
    |> Kernel.+(1..time |> Enum.random())
  end

  def random_epoch_timer do
    1..10
    |> Enum.random()
    |> Kernel.*(@epoch_time_avg)
  end
end
