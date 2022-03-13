defmodule Albagen.Core.Wallet do
  require Logger
  alias Albagen.RPC

  @wait_for_balance_delay :timer.seconds(5)

  @doc """
  Imports the account if it is not yet imported
  """
  def ensure_wallet_imported(host, address, key) do
    host
    |> RPC.is_account_imported(address)
    |> import_account?(host, key)
  end

  defp import_account?({:ok, false}, host, key) do
    host
    |> RPC.import_account(key)
  end

  defp import_account?({:ok, true}, _host, _key), do: {:ok, "Account is already imported"}

  defp import_account?(error, _host, _key), do: error

  @doc """
  Unlocks the account if it is not yet unlocked
  """
  def ensure_wallet_unlocked(host, address) do
    host
    |> RPC.is_account_unlocked(address)
    |> unlock_account?(host, address)
  end

  defp unlock_account?({:ok, false}, host, address) do
    host
    |> RPC.unlock_account(address)
  end

  defp unlock_account?({:ok, true}, _host, _address), do: {:ok, "Account is already unlocked"}

  defp unlock_account?(error, _host, _address), do: error

  @doc """
  Waits untill the given account has a balance higher than zero
  """
  def wait_for_balance(host, address, attempt \\ 1)

  def wait_for_balance(_host, _address, attempt) when attempt > 10,
    do: {:error, :no_balance_after_waiting}

  def wait_for_balance(host, address, attempt) do
    case RPC.get_account(host, address) do
      {:ok, %{"balance" => 0}} ->
        Logger.debug("Balance not yet received, waiting...")
        Process.sleep(@wait_for_balance_delay)
        wait_for_balance(host, address, attempt + 1)

      {:ok, _balance} ->
        :ok

      error ->
        error
    end
  end

  @doc """
  Returns balance for given address
  """
  def get_balance(host, address) do
    case RPC.get_account(host, address) do
      {:ok, %{"balance" => balance}} ->
        {:ok, balance}

      {:ok, no_match} ->
        Logger.debug("No balance found: #{inspect(no_match)}")
        {:error, :no_balance_found}

      error ->
        error
    end
  end
end
