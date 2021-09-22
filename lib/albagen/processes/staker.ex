defmodule Albagen.Processes.Staker do
  require Logger
  use GenServer

  alias Albagen.Model.Account

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

  def new(account) do
    case GenServer.whereis({:global, {__MODULE__, account.address}}) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        {__MODULE__, {:new, account}}
        |> start_staker()
    end
  end

  def load(account) do
    case GenServer.whereis({:global, {__MODULE__, account.address}}) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        {__MODULE__, {:from_db, account}}
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

  def start_link(args = {_source, account}) do
    GenServer.start_link(__MODULE__, args, name: {:global, {__MODULE__, account.address}})
  end

  def init({_source, account}) do
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
        Process.send_after(self(), :send_transaction, initial_timer(account.seed_number))
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

    with {:ok, _result} <- Albagen.RPC.import_account(node, private_key),
         {:ok, _} <-
           Albagen.RPC.send_basic_transaction(
             node,
             address,
             balance
           ),
         :ok <- balance_received(node, address),
         {:ok, _result} <- Account.set_seeded(address) do
      Logger.info("Account has been imported and received initial balance #{balance}")

      {:noreply,
       %{state | timer: Process.send_after(self(), :send_transaction, random_epoch_timer())}}
    end
  end

  def handle_info(:send_transaction, state), do: {:noreply, state}

  defp balance_received(client, account_address) do
    case Albagen.RPC.get_account(client, account_address) do
      {:ok, %{"basic" => %{"balance" => 0}}} ->
        Process.sleep(30_000)
        balance_received(client, account_address)

      {:ok, _balance} ->
        :ok

      {:error, reason} ->
        {:error, reason}
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
