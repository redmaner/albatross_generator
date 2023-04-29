defmodule Albagen.Core.Faucet do
  @moduledoc """
  Interactions with the Nimiq faucet
  """

  @faucet_url Application.compile_env(:albagen, :faucet_url)

  def request_funds(address) do
    Finch.build(
      :post,
      @faucet_url,
      [{"content-type", "application/x-www-form-urlencoded"}],
      form_data_encode(address)
    )
    |> Finch.request(:faucet_client)
    |> check_faucet_status()
  end

  defp form_data_encode(address) do
    URI.encode_query([{"address", address}]) |> :binary.bin_to_list()
  end

  defp check_faucet_status({:ok, %Finch.Response{body: body, status: 200}}) do
    case Jason.decode(body) do
      {:ok, %{"success" => true}} -> :ok
      {:ok, data} -> {:error, data}
      error -> error
    end
  end

  defp check_faucet_status({:ok, %Finch.Response{body: body}}), do: {:error, body}

  defp check_faucet_status(error), do: error
end
