defmodule Albagen.DB do
  @moduledoc """
  A Simple Sqlite3 server to interact with the Sqlite DB file
  """
  require Logger

  @behaviour NimblePool

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    NimblePool.start_link(
      worker: {Albagen.DB, :init},
      pool_size: 4,
      lazy: false
    )
  end

  def query(sql, args \\ [], timeout \\ 10_000) do
    NimblePool.checkout!(__MODULE__, :get_db_conn, fn _from, conn ->
      case :esqlite3.q(sql, args, conn, timeout) do
        rows when is_list(rows) -> {{:ok, rows}, conn}
        error -> {error, conn}
      end
    end)
  end

  @impl true
  def init_pool(_opts) do
    Process.register(self(), __MODULE__)
    database_file = Albagen.Config.sqlite_path() |> String.to_charlist()
    {:ok, database_file}
  end

  @impl true
  def init_worker(database_file) do
    Logger.debug("Starting Sqlite worker")

    case :esqlite3.open(database_file) do
      {:ok, conn} -> {:ok, conn, database_file}
      {:error, reason} -> raise reason
    end
  end

  @impl true
  def handle_checkout(:get_db_conn, _from, conn, pool_state) do
    {:ok, conn, conn, pool_state}
  end

  @impl true
  def handle_checkin(conn, _from, _old_conn, pool_state) do
    {:ok, conn, pool_state}
  end

  @impl true
  def terminate_worker(reason, conn, pool_state) do
    Logger.warn("Terminating Sqlite worker. Reason: #{inspect(reason)}")
    :esqlite3.close(conn)
    {:ok, pool_state}
  end
end
