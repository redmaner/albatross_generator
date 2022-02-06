defmodule Albagen.Processes.Staker do
  require Logger
  use GenServer

  alias Albagen.Core.Wallet
  alias Albagen.Model.Account
  alias Albagen.RPC

  @epoch_time_avg :timer.seconds(20)
  @nim_in_luna 100_000
  @balance_min 1 * @nim_in_luna
  @basic_actions [:keep, :unstake, :update]

  @doc """
  create a new staker from scratch
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
        |> has_account_balance?(balance)
        |> Enum.random()
        |> do_transaction(staker, balance, state)

      {:error, :no_staker_found} ->
        do_transaction(:new_staker, nil, balance, state)

      {:error, _method, reason} ->
        Logger.error("Failed to retrieve staker: #{inspect(reason)}")

        {:noreply,
         %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
    end
  end

  defp has_account_balance?(actions, balance) when balance > @balance_min, do: [:stake | actions]
  defp has_account_balance?(actions, _balance), do: actions

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

      {:error, _method, reason} ->
        Logger.error("Failed to send new staker transaction: #{inspect(reason)}")
    end

    {:noreply,
     %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
  rescue
    RuntimeError ->
      Logger.error("Failed to get active validators")

      {:noreply,
       %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
  end

  defp do_transaction(
         :keep,
         %{"balance" => stake_balance, "delegation" => delegation},
         _balance,
         state
       ) do
    Logger.info("Action: keep => stake: #{stake_balance} Luna, validator: #{delegation}")

    {:noreply,
     %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
  end

  # TODO:
  # Verify we have enough funds in the staking balance
  # to pay for the update transaction
  defp do_transaction(
         :update,
         %{"delegation" => old_validator},
         _balance,
         state = %{account: %Account{address: address, node: host}}
       ) do
    new_validator = select_active_validator(host, old_validator)

    case RPC.send_update_staker_transaction(host, address, new_validator) do
      {:ok, _return} ->
        Logger.info(
          "Action: update => moved stake from old validator #{old_validator} to new validator #{new_validator}"
        )

      {:error, _method, reason} ->
        Logger.error("Failed to update stake: #{inspect(reason)}")
    end

    {:noreply,
     %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
  rescue
    RuntimeError ->
      Logger.error("Failed to get active validators")

      {:noreply,
       %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
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

      {:error, _method, reason} ->
        Logger.error("Failed to send unstake transaction: #{inspect(reason)}")
    end

    {:noreply,
     %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
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

      {:error, _method, reason} ->
        Logger.error("Failed to send stake transaction: #{inspect(reason)}")
    end

    {:noreply,
     %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
  end

  def select_active_validator(host, current_validator \\ nil) do
    case Albagen.RPC.list_stakes(host) do
      {:ok, validators} when is_map(validators) and validators != %{} ->
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
    do: validators |> Map.drop([current_validator])

  defp extract_validator({delegation, _balance}), do: delegation

  defp extract_validator(_), do: raise("No validator found")

  def initial_timer(seed_number, time \\ :timer.seconds(20)) do
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
