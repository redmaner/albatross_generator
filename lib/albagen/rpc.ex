defmodule Albagen.RPC do
  alias Jsonrpc.Request
  import Jsonrpc

  def list_stakes(host) do
    Request.new(method: "listStakes")
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        list_stakes(host)

      {:error, reason} ->
        {:error, :list_stakes, reason}

      return ->
        return
    end
  end

  def get_latest_block_number(host) do
    Request.new(method: "getBlockNumber")
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        get_latest_block_number(host)

      {:error, reason} ->
        {:error, :get_latest_block_number, reason}

      return ->
        return
    end
  end

  def import_account(host, key) do
    Request.new(method: "importRawKey", params: [key, nil])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        import_account(host, key)

      {:error, reason} ->
        {:error, :import_account, reason}

      return ->
        return
    end
  end

  def unlock_account(host, address) do
    Request.new(method: "unlockAccount", params: [address, nil, nil])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        unlock_account(host, address)

      {:error, reason} ->
        {:error, :unlock_account, reason}

      return ->
        return
    end
  end

  def lock_account(host, address) do
    Request.new(method: "lockAccount", params: [address])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        lock_account(host, address)

      {:error, reason} ->
        {:error, :lock_account, reason}

      return ->
        return
    end
  end

  def create_account(host) do
    Request.new(method: "createAccount", params: [""])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        create_account(host)

      {:error, reason} ->
        {:error, :create_account, reason}

      return ->
        return
    end
  end

  def get_account(host, address) do
    Request.new(method: "getAccount", params: [address])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        get_account(host, address)

      {:error, reason} ->
        {:error, :get_account, reason}

      return ->
        return
    end
  end

  def send_basic_transaction(host, recipient, value) do
    wallet = Albagen.Config.seed_wallet_addres()
    tx_fee = create_basic_transaction(host, wallet, recipient, value) |> extract_tx_fee()

    if tx_fee < value do
      Request.new(
        method: "sendBasicTransaction",
        params: [wallet, recipient, value - tx_fee, tx_fee, "+0"]
      )
      |> call(name: :nimiq, url: host)
      |> case do
        {:error, %Mint.TransportError{reason: :timeout}} ->
          Process.sleep(2000)
          send_basic_transaction(host, recipient, value)

        {:error, reason} ->
          {:error, :send_basic_transaction, reason}

        return ->
          return
      end
    else
      {:error, :insufficient_fees}
    end
  end

  defp create_basic_transaction(host, wallet, recipient, value) do
    Request.new(method: "createBasicTransaction", params: [wallet, recipient, value, 0, "+0"])
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        create_basic_transaction(host, wallet, recipient, value)

      {:error, reason} ->
        {:error, :send_basic_transaction, reason}

      return ->
        return
    end
  end

  def send_new_staker_transaction(host, wallet, delegation, value) do
    tx_fee = create_new_staker_transaction(host, wallet, delegation, value) |> extract_tx_fee()

    if tx_fee < value do
      Request.new(
        method: "sendNewStakerTransaction",
        params: [wallet, delegation, value - tx_fee, tx_fee, "+0"]
      )
      |> call(name: :nimiq, url: host)
      |> case do
        {:error, %Mint.TransportError{reason: :timeout}} ->
          Process.sleep(2000)
          send_new_staker_transaction(host, wallet, delegation, value)

        {:error, reason} ->
          {:error, :send_new_staker_transaction, reason}

        return ->
          return
      end
    end
  end

  defp create_new_staker_transaction(host, wallet, delegation, value) do
    Request.new(
      method: "createNewStakerTransaction",
      params: [wallet, delegation, value, 0, "+0"]
    )
    |> call(name: :nimiq, url: host)
    |> case do
      {:error, %Mint.TransportError{reason: :timeout}} ->
        Process.sleep(2000)
        create_new_staker_transaction(host, wallet, delegation, value)

      {:error, reason} ->
        {:error, :create_new_staker_transaction, reason}

      return ->
        return
    end
  end

  defp extract_tx_fee({:ok, raw_tx}) do
    raw_tx
    |> Hexate.decode()
    |> byte_size()
  end

  defp extract_tx_fee(error), do: error
end
