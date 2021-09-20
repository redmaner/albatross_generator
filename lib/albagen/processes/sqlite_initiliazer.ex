defmodule Albagen.Processes.SqliteInitializer do
  use GenServer

  def init(_opts) do
    {:ok, %{}, {:continue, :create_tables}}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def handle_continue(:create_tables, state) do
    {:ok, _result} =
      Sqlitex.Server.query(
        :albagen_sqlite,
        "CREATE TABLE IF NOT EXISTS stakers(address TEXT PRIMARY KEY NOT NULL, public_key TEXT NOT NULL, private_key TEXT NOT NULL, node TEXT NOT NULL, validator TEXT NOT NULL);"
      )

    {:noreply, state}
  end
end
