defmodule Albagen.RPC do
  require Logger

  def list_stakes(host) do
    Nimiqex.Blockchain.get_active_validators()
    |> make_rpc_call(host)
  end

  def get_latest_block_number(host) do
    Nimiqex.Blockchain.get_block_number()
    |> make_rpc_call(host)
  end

  def import_account(host, key) do
    Nimiqex.Wallet.import_raw_key(key, nil)
    |> make_rpc_call(host)
  end

  def is_account_imported(host, address) do
    Nimiqex.Wallet.is_account_imported(address)
    |> make_rpc_call(host)
  end

  def unlock_account(host, address) do
    Nimiqex.Wallet.unlock_account(address, nil, nil)
    |> make_rpc_call(host)
  end

  def is_account_unlocked(host, address) do
    Nimiqex.Wallet.is_account_unlocked(address)
    |> make_rpc_call(host)
  end

  def lock_account(host, address) do
    Nimiqex.Wallet.lock_account(address)
    |> make_rpc_call(host)
  end

  def create_account(host) do
    Nimiqex.Wallet.create_account("")
    |> make_rpc_call(host)
  end

  def get_account(host, address) do
    Nimiqex.Blockchain.get_account_by_address(address)
    |> make_rpc_call(host)
  end

  def get_staker(host, address) do
    Nimiqex.Blockchain.get_staker_by_address(address)
    |> make_rpc_call(host)
    |> case do
      {:error, "getStakerByAddress", %Jsonrpc.Error{data: error_message}} = error ->
        if error_message |> String.match?(~r(^No staker with address:)) do
          {:error, :no_staker_found}
        else
          error
        end

      return ->
        return
    end
  end

  def send_basic_transaction(host, recipient, value) do
    wallet = Albagen.Config.seed_wallet_addres()
    tx_fee = create_basic_transaction(host, wallet, recipient, value) |> extract_tx_fee()

    if tx_fee < value do
      Nimiqex.Consensus.send_basic_transaction(wallet, recipient, value - tx_fee, tx_fee, "+0")
      |> make_rpc_call(host)
    else
      {:error, :insufficient_fees}
    end
  end

  defp create_basic_transaction(host, wallet, recipient, value) do
    Nimiqex.Consensus.create_basic_transaction(wallet, recipient, value, 0, "+0")
    |> make_rpc_call(host)
  end

  def send_new_staker_transaction(host, wallet, delegation, value) do
    tx_fee = create_new_staker_transaction(host, wallet, delegation, value) |> extract_tx_fee()

    if tx_fee < value do
      Nimiqex.Consensus.send_new_staker_transaction(
        wallet,
        wallet,
        delegation,
        value - tx_fee,
        tx_fee,
        "+0"
      )
      |> make_rpc_call(host)
    end
  end

  defp create_new_staker_transaction(host, wallet, delegation, value) do
    Nimiqex.Consensus.create_new_staker_transaction(wallet, wallet, delegation, value, 0, "+0")
    |> make_rpc_call(host)
  end

  def send_stake_transaction(host, wallet, value) do
    tx_fee = create_stake_transaction(host, wallet, value) |> extract_tx_fee()

    if tx_fee < value do
      Nimiqex.Consensus.send_stake_transaction(
        wallet,
        wallet,
        value - tx_fee,
        tx_fee,
        "+0"
      )
      |> make_rpc_call(host)
    end
  end

  defp create_stake_transaction(host, wallet, value) do
    Nimiqex.Consensus.create_stake_transaction(wallet, wallet, value, 0, "+0")
    |> make_rpc_call(host)
  end

  def send_update_staker_transaction(host, wallet, new_delegation) do
    tx_fee = create_update_staker_transaction(host, wallet, new_delegation) |> extract_tx_fee()

    Nimiqex.Consensus.send_update_transaction(wallet, wallet, new_delegation, tx_fee, "+0")
    |> make_rpc_call(host)
  end

  defp create_update_staker_transaction(host, wallet, new_delegation) do
    Nimiqex.Consensus.create_update_transaction(wallet, wallet, new_delegation, 0, "+0")
    |> make_rpc_call(host)
  end

  def send_unstake_transaction(host, wallet, value) do
    tx_fee = create_unstake_transaction(host, wallet, value) |> extract_tx_fee()

    if tx_fee < value do
      Nimiqex.Consensus.send_unstake_transaction(
        wallet,
        wallet,
        value - tx_fee,
        tx_fee,
        "+0"
      )
      |> make_rpc_call(host)
    end
  end

  defp create_unstake_transaction(host, wallet, value) do
    Nimiqex.Consensus.create_unstake_transaction(wallet, wallet, value, 0, "+0")
    |> make_rpc_call(host)
  end

  defp make_rpc_call(request = %Jsonrpc.Request{method: method}, host) do
    request
    |> Nimiqex.send(:albagen_rpc_client, host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Logger.warn("Timeout when executing request #{method}, retrying in 3 seconds")
        Process.sleep(3000)
        make_rpc_call(request, host)

      {:error, %Finch.Error{reason: :request_timeout}} ->
        Logger.warn("Timeout when executing request #{method}, retrying in 3 seconds")
        Process.sleep(3000)
        make_rpc_call(request, host)

      {:error, reason} ->
        {:error, method, reason}

      return ->
        return
    end
  catch
    :exit, _ ->
      Process.sleep(2000)
      make_rpc_call(request, host)
  end

  defp extract_tx_fee({:ok, raw_tx}) do
    raw_tx
    |> Hexate.decode()
    |> byte_size()
  end

  defp extract_tx_fee(error), do: error
end
