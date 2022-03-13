defmodule Albagen.Model.Account do
  require Logger
  use GenServer

  @type t :: %__MODULE__{
          address: String.t(),
          public_key: String.t(),
          private_key: String.t(),
          node: String.t(),
          seed_number: integer()
        }

  defstruct ~w[address public_key private_key node seed_number]a

  def parse_from_json(
        %{"address" => address, "privateKey" => private_key, "publicKey" => public_key},
        node,
        seed_number
      ) do
    {:ok,
     %__MODULE__{
       address: address,
       public_key: public_key,
       private_key: private_key,
       node: node,
       seed_number: seed_number
     }}
  end

  def init(_opts) do
    database_file = Albagen.Config.sqlite_path() |> String.to_charlist()

    case :esqlite3.open(database_file) do
      {:ok, conn} ->
        state = %{
          conn: conn,
          buffer: [],
          timer: :erlang.send_after(180_000, self(), :write_accounts)
        }

        {:ok, state}

      {:error, reason} ->
        raise reason
    end
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def query(sql, args \\ [], timeout \\ 10_000) do
    GenServer.call(__MODULE__, {:query, sql, args, timeout}, timeout)
  end

  def buffer(account) do
    GenServer.cast(__MODULE__, {:buffer, account})
  end

  def create_table do
    query(
      "CREATE TABLE IF NOT EXISTS stakers(address TEXT PRIMARY KEY NOT NULL, public_key TEXT NOT NULL, private_key TEXT NOT NULL, node TEXT NOT NULL, seed_number INTEGER NOT NULL);"
    )
  end

  def count_created_stakers do
    case query("SELECT COUNT(*) AS count_stakers FROM stakers") do
      {:ok, [{count_stakers}]} -> {:ok, count_stakers}
      {:ok, _result} -> {:ok, 0}
      error -> error
    end
  end

  def get_all do
    query("SELECT * FROM stakers ORDER BY seed_number")
    |> wrap_multi_return()
  end

  defp wrap_multi_return({:ok, rows}) do
    return =
      rows
      |> Enum.map(&parse_account_from_row/1)

    {:ok, return}
  end

  defp wrap_multi_return(error), do: error

  defp parse_account_from_row({
         address,
         public_key,
         private_key,
         node,
         seed_number
       }) do
    %Albagen.Model.Account{
      address: address,
      public_key: public_key,
      private_key: private_key,
      node: node,
      seed_number: seed_number
    }
  end

  def handle_call({:query, sql, args, timeout}, _from, state = %{conn: conn}) do
    case :esqlite3.q(sql, args, conn, timeout) do
      rows when is_list(rows) -> {:reply, {:ok, rows}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_cast({:buffer, account}, state = %{buffer: buffer}) do
    {:noreply, %{state | buffer: [account | buffer]}}
  end

  def handle_info(:write_accounts, state = %{buffer: buffer}) when buffer == [] do
    {:noreply, %{state | timer: :erlang.send_after(180_000, self(), :write_accounts)}}
  end

  def handle_info(:write_accounts, state = %{buffer: accounts, conn: conn}) do
    sql = create_multi_insert_query(accounts)

    case :esqlite3.q(sql, [], conn, 30_000) do
      rows when is_list(rows) ->
        Logger.debug("Written #{Enum.count(accounts)} accounts to Sqlite")

        {:noreply,
         %{state | buffer: [], timer: :erlang.send_after(180_000, self(), :write_accounts)}}

      error ->
        Logger.error("Failed to write accounts to sqlite: #{inspect(error)}")
        {:noreply, %{state | timer: :erlang.send_after(180_000, self(), :write_accounts)}}
    end
  end

  def create_multi_insert_query(
        accounts,
        query \\ "INSERT INTO stakers (address, public_key, private_key, node, seed_number) VALUES"
      )

  def create_multi_insert_query(
        [
          %__MODULE__{
            address: address,
            public_key: public_key,
            private_key: private_key,
            node: node,
            seed_number: seed_number
          }
          | []
        ],
        query
      ) do
    query <> " ('#{address}','#{public_key}','#{private_key}','#{node}',#{seed_number});"
  end

  def create_multi_insert_query(
        [
          %__MODULE__{
            address: address,
            public_key: public_key,
            private_key: private_key,
            node: node,
            seed_number: seed_number
          }
          | accounts
        ],
        query
      ) do
    create_multi_insert_query(
      accounts,
      query <> " ('#{address}','#{public_key}','#{private_key}','#{node}',#{seed_number}),"
    )
  end
end
