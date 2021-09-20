defmodule Albagen.Processes.WalletCreator do
  require Logger

  @nim_in_luna 100_000

  def create(seed_number) do
    client = Albagen.Config.albatross_nodes() |> Enum.random()
    validator = get_validator(client)
    balance = Enum.random(1..1000) * @nim_in_luna
    stake_percentage = Enum.random(1..100)
    stake_balance = (balance * stake_percentage / 100) |> floor()

    with {:ok, wallet} <- Albagen.RPC.create_account(client),
         {:ok, account} <- Albagen.Model.Account.parse_from_json(wallet, client, validator),
         :ok <- Logger.info("Created account", address: account.address, seed: seed_number),
         {:ok, _} <-
           Albagen.RPC.send_basic_transaction(
             client,
             account.address,
             balance
           ),
         :ok <- balance_received(client, account.address),
         :ok <-
           Logger.info("Account has received balance #{balance}",
             address: account.address,
             seed: seed_number
           ),
         {:ok, _} <- Albagen.RPC.import_account(client, account.private_key),
         {:ok, _} <- Albagen.RPC.unlock_account(client, account.address),
         :ok <-
           Logger.info("Account has been imported and unlocked",
             address: account.address,
             seed: seed_number
           ),
         {:ok, _} <-
           Albagen.RPC.send_new_staker_transaction(
             client,
             account.address,
             validator,
             stake_balance
           ),
         :ok <-
           Logger.info(
             "Account started staking with balance #{stake_balance} to validator #{validator}",
             address: account.address,
             seed: seed_number
           ),
         {:ok, _} <- Albagen.RPC.lock_account(client, account.address),
         {:ok, _result} <- insert_into_sqlite(account) do
      :ok
    else
      {:error, call, reason} ->
        Logger.error("Encountered error for call #{call}: #{inspect(reason)}")

      {:error, reason} ->
        Logger.error("Encountered error: #{inspect(reason)}")
    end
  end

  defp insert_into_sqlite(account) do
    Sqlitex.Server.query(
      :albagen_sqlite,
      "INSERT INTO stakers (address, public_key, private_key, node, validator) VALUES (?, ?, ?, ?, ?)",
      bind: [
        account.address,
        account.public_key,
        account.private_key,
        account.node,
        account.validator
      ]
    )
  end

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

  def get_validator(host) do
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
end
