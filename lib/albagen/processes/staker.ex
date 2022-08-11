defmodule Albagen.Processes.Staker do
  require Logger
  use GenServer

  alias Albagen.Config
  alias Albagen.Core.Wallet
  alias Albagen.Model.Account
  alias Albagen.RPC

  @nim_in_luna 100_000
  @balance_min 1 * @nim_in_luna
  @basic_actions [:unstake, :update]

  @doc """
  Create stakers by a range. This function is ran in a Task
  """
  def create_by_range(range) do
    :telemetry.execute([:albagen, :task], %{action: "add", number: 1})

    range
    |> Enum.each(&create/1)

    Logger.debug("Task completed")
    :telemetry.execute([:albagen, :task], %{action: "remove", number: 1})
  end

  @doc """
  Creates a new staker and starts a staker process
  """
  def create(seed_number) do
    client = Albagen.Config.albatross_nodes() |> Enum.random()

    with {:ok, wallet} <- Albagen.RPC.create_account(client),
         {:ok, account} <- Albagen.Model.Account.parse_from_json(wallet, client, seed_number),
         :ok <- Logger.info("New account created", address: account.address, seed: seed_number),
         :ok <- Account.buffer(account),
         {:ok, _pid} <- load(account) do
      :ok
    else
      {:error, call, reason} ->
        Logger.error("Encountered error for call #{call}: #{inspect(reason)}")

      {:error, reason} ->
        Logger.error("Encountered error: #{inspect(reason)}")
    end
  end

  @doc """
  Loads a staker process. This is either called after a
  staker is created, or when a staker is loaded from Sqlite
  """
  def load(account = %Account{address: address}) do
    case GenServer.whereis(name(address)) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {__MODULE__, account} |> start_staker()
    end
  end

  defp start_staker(child_spec) do
    case DynamicSupervisor.start_child(Albagen.Processes.StakerSupervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      _ = error -> {:error, "#{inspect(error)}"}
    end
  end

  defp name(address), do: {:global, {__MODULE__, address}}

  def start_link(account = %Account{address: address}) do
    GenServer.start_link(__MODULE__, account, name: name(address))
  end

  def init(account = %Account{seed_number: seed_number}) do
    Logger.metadata(address: account.address)
    Logger.metadata(seed: seed_number)

    # On initial startup of a staker process the staker process is
    # scheduled randomly between now and the next 15 minutes
    # this is done to spread processes evenly and prevent thundering
    # herd on both Albatross nodes and the Erlang VM
    state = %{
      account: account,
      timer: schedule_staker(:timer.minutes(15))
    }

    Logger.info("Staker process started")

    {:ok, state}
  end

  def handle_info(
        :send_transaction,
        state = %{
          account: %Account{address: address, node: host, private_key: private_key}
        }
      ) do
    with {:ok, _result} <- Wallet.ensure_wallet_imported(host, address, private_key),
         {:ok, _result} <- Wallet.ensure_wallet_unlocked(host, address),
         {:ok, balance} <- Wallet.get_balance(host, address) do
      select_next_transaction(balance, state)
    else
      {:error, method, reason} ->
        Logger.error(
          "Encountered error during transaction setup: #{method} --> #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  defp select_next_transaction(
         balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    case RPC.get_staker(host, address) do
      {:ok, staker} ->
        Logger.info(
          "Current stake => stake balance: #{staker["balance"]}, delegation: #{staker["delegation"]} account balance: #{balance}"
        )

        @basic_actions
        |> is_action_keep_allowed?(Config.allow_action_keep())
        |> has_account_balance?(balance)
        |> Enum.random()
        |> do_transaction(staker, balance, state)

      {:error, :no_staker_found} when balance == 0 ->
        Logger.debug("Account has no funds, start seeding account")
        do_transaction(:seed_account, nil, 0, state)

      {:error, :no_staker_found} ->
        do_transaction(:new_staker, nil, balance, state)

      {:error, _method, reason} ->
        Logger.error("Failed to retrieve staker: #{inspect(reason)}")

        {:noreply, %{state | timer: schedule_staker()}}
    end
  end

  defp is_action_keep_allowed?(actions, true), do: [:keep | actions]
  defp is_action_keep_allowed?(actions, false), do: actions

  defp has_account_balance?(actions, balance) when balance > @balance_min, do: [:stake | actions]
  defp has_account_balance?(actions, _balance), do: actions

  defp do_transaction(
         :seed_account,
         nil,
         0,
         state = %{account: %Account{address: address, node: host}}
       ) do
    min_nim = Config.new_account_min_nim() * @nim_in_luna
    max_nim = Config.new_account_max_nim() * @nim_in_luna

    balance = Enum.random(min_nim..max_nim)

    with {:ok, _} <- Albagen.RPC.send_basic_transaction(host, address, balance),
         :ok <- Wallet.wait_for_balance(host, address) do
      Logger.info("Action: seed_account => balance: #{balance}")
      :telemetry.execute([:albagen, :tx], %{value: 1})

      {:noreply, %{state | timer: schedule_staker()}}
    else
      {:error, method, reason} ->
        Logger.error("Seeding account failed during #{method}: #{inspect(reason)}")

        # TODO: check the method and maybe retry
        {:stop, :seeding_failed, state}

      error ->
        Logger.error("Unhandled error when seeding account: #{inspect(error)}")
        {:noreply, state}
    end
  end

  defp do_transaction(
         :new_staker,
         nil,
         balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    new_validator = select_active_validator(host)
    stake_percentage = [10, 25, 50, 75, 100] |> Enum.random()
    stake_amount = (balance * stake_percentage / 100) |> round()

    case RPC.send_new_staker_transaction(host, address, new_validator, stake_amount) do
      {:ok, _return} ->
        Logger.info(
          "Action: new_staker => stake: #{stake_amount} Luna, validator #{new_validator}"
        )

        :telemetry.execute([:albagen, :tx], %{value: 1})

      {:error, _method, reason} ->
        Logger.error("Failed to send new staker transaction: #{inspect(reason)}")
    end

    {:noreply, %{state | timer: schedule_staker()}}
  rescue
    RuntimeError ->
      Logger.error("Failed to get active validators")

      {:noreply, %{state | timer: schedule_staker()}}
  end

  defp do_transaction(
         :keep,
         %{"balance" => stake_balance, "delegation" => delegation},
         _balance,
         state
       ) do
    Logger.info("Action: keep => stake: #{stake_balance} Luna, validator: #{delegation}")

    {:noreply, %{state | timer: schedule_staker()}}
  end

  # TODO:
  # Verify we have enough funds in the staking balance
  # to pay for the update transaction
  defp do_transaction(
         :update,
         staker,
         _balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    old_validator = staker["delegation"]
    new_validator = select_active_validator(host, old_validator)

    case RPC.send_update_staker_transaction(host, address, new_validator) do
      {:ok, _return} ->
        Logger.info(
          "Action: update => moved stake from old validator #{old_validator} to new validator #{new_validator}"
        )

        :telemetry.execute([:albagen, :tx], %{value: 1})

      {:error, _method, reason} ->
        Logger.error("Failed to update stake: #{inspect(reason)}")
    end

    {:noreply, %{state | timer: schedule_staker()}}
  rescue
    RuntimeError ->
      Logger.error("Failed to get active validators")

      {:noreply, %{state | timer: schedule_staker()}}
  end

  defp do_transaction(
         :unstake,
         %{"balance" => stake_balance},
         _balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    unstake_percentage = [10, 25, 50, 75, 100] |> Enum.random()
    unstake_amount = (stake_balance * unstake_percentage / 100) |> round()

    case RPC.send_unstake_transaction(host, address, unstake_amount) do
      {:ok, _return} ->
        Logger.info(
          "Action: unstake => decreased stake with #{unstake_amount} (#{unstake_percentage}%)"
        )

        :telemetry.execute([:albagen, :tx], %{value: 1})

      {:error, _method, reason} ->
        Logger.error("Failed to send unstake transaction: #{inspect(reason)}")
    end

    {:noreply, %{state | timer: schedule_staker()}}
  end

  defp do_transaction(
         :stake,
         _staker,
         balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    stake_percentage = [10, 25, 50, 75, 100] |> Enum.random()
    stake_amount = (balance * stake_percentage / 100) |> round()

    case RPC.send_stake_transaction(host, address, stake_amount) do
      {:ok, _return} ->
        Logger.info("Action: stake => increased stake with #{stake_amount}")

        :telemetry.execute([:albagen, :tx], %{value: 1})

      {:error, _method, reason} ->
        Logger.error("Failed to send stake transaction: #{inspect(reason)}")
    end

    {:noreply, %{state | timer: schedule_staker()}}
  end

  def select_active_validator(host, current_validator \\ nil) do
    case Albagen.RPC.list_stakes(host) do
      {:ok, validators} when is_list(validators) and validators != [] ->
        validators
        |> drop_current_validator(current_validator)
        |> Enum.random()
        |> extract_validator()

      _error ->
        raise "Retrieving active validator failed"
    end
  end

  defp drop_current_validator(validators, nil), do: validators

  defp drop_current_validator(validators, current_validator),
    do: validators |> Enum.reject(fn %{"address" => address} -> address == current_validator end)

  defp extract_validator(%{"address" => address}), do: address

  defp extract_validator(_), do: raise("No validator found")

  defp schedule_staker(time) do
    next = 0..time |> Enum.random()
    :erlang.send_after(next, self(), :send_transaction)
  end

  defp schedule_staker do
    timer_cap = Config.timer_cap_in_secs()

    next = 0..timer_cap |> Enum.random()

    :erlang.send_after(next, self(), :send_transaction)
  end
end
