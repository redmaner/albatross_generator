defmodule Albagen.RPC do
  alias Jsonrpc.Request
  import Jsonrpc

  def list_stakes(host) do
    Request.new(method: "listStakes")
    |> make_rpc_call(host)
  end

  def get_latest_block_number(host) do
    Request.new(method: "getBlockNumber")
    |> make_rpc_call(host)
  end

  def import_account(host, key) do
    Request.new(method: "importRawKey", params: [key, nil])
    |> make_rpc_call(host)
  end

  def unlock_account(host, address) do
    Request.new(method: "unlockAccount", params: [address, nil, nil])
    |> make_rpc_call(host)
  end

  def lock_account(host, address) do
    Request.new(method: "lockAccount", params: [address])
    |> make_rpc_call(host)
  end

  def create_account(host) do
    Request.new(method: "createAccount", params: [""])
    |> make_rpc_call(host)
  end

  def get_account(host, address) do
    Request.new(method: "getAccount", params: [address])
    |> make_rpc_call(host)
  end

  def get_staker(host, address) do
    Request.new(method: "getStaker", params: [address])
    |> make_rpc_call(host)
  end

  def send_basic_transaction(host, recipient, value) do
    wallet = Albagen.Config.seed_wallet_addres()
    tx_fee = create_basic_transaction(host, wallet, recipient, value) |> extract_tx_fee()

    if tx_fee < value do
      Request.new(
        method: "sendBasicTransaction",
        params: [wallet, recipient, value - tx_fee, tx_fee, "+0"]
      )
      |> make_rpc_call(host)
    else
      {:error, :insufficient_fees}
    end
  end

  defp create_basic_transaction(host, wallet, recipient, value) do
    Request.new(method: "createBasicTransaction", params: [wallet, recipient, value, 0, "+0"])
    |> make_rpc_call(host)
  end

  def send_new_staker_transaction(host, wallet, delegation, value) do
    tx_fee = create_new_staker_transaction(host, wallet, delegation, value) |> extract_tx_fee()

    if tx_fee < value do
      Request.new(
        method: "sendNewStakerTransaction",
        params: [wallet, delegation, value - tx_fee, tx_fee, "+0"]
      )
      |> make_rpc_call(host)
    end
  end

  defp create_new_staker_transaction(host, wallet, delegation, value) do
    Request.new(
      method: "createNewStakerTransaction",
      params: [wallet, delegation, value, 0, "+0"]
    )
    |> make_rpc_call(host)
  end

  defp make_rpc_call(request = %Jsonrpc.Request{method: method}, host) do
    # TODO
    # Add custom headers to support password protected RPC servers

    request
    |> call(name: :nimiq, url: host, pool_timeout: 15_000, receive_timeout: 15_000)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(3000)
        make_rpc_call(request, host)

      {:error, %Finch.Error{reason: :request_timeout}} ->
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
