defmodule Albagen.Processes.Observer do
  require Logger

  use GenServer

  def init(_opts) do
    state = %{
      tasks: 0,
      txs: 0,
      last_flush: System.os_time(:millisecond),
      timer_stakers: Process.send_after(self(), :observe_stakers, 300_000),
      timer_txs: Process.send_after(self(), :observe_txs, 120_000)
    }

    :ok =
      :telemetry.attach(
        "albagen_staker_observer",
        [:albagen, :task],
        &Albagen.Processes.Observer.handle_event/4,
        nil
      )

    :ok =
      :telemetry.attach(
        "albagen_txs_observer",
        [:albagen, :tx],
        &Albagen.Processes.Observer.handle_event/4,
        nil
      )

    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def handle_event([:albagen, :task], %{action: "add", number: 1}, _metadata, _config) do
    GenServer.cast(__MODULE__, :add_task)
  end

  def handle_event([:albagen, :task], %{action: "remove", number: 1}, _metadata, _config) do
    GenServer.cast(__MODULE__, :remove_task)
  end

  def handle_event([:albagen, :tx], %{value: 1}, _metadata, _config) do
    GenServer.cast(__MODULE__, :add_tx)
  end

  def handle_cast(:add_task, state = %{tasks: tasks}) do
    {:noreply, %{state | tasks: tasks + 1}}
  end

  def handle_cast(:remove_task, state = %{tasks: tasks}) do
    {:noreply, %{state | tasks: tasks - 1}}
  end

  def handle_cast(:add_tx, state = %{txs: txs}) do
    {:noreply, %{state | txs: txs + 1}}
  end

  def handle_info(:observe_stakers, state = %{tasks: tasks}) do
    with %{active: stakers_running} <-
           DynamicSupervisor.count_children(Albagen.Processes.StakerSupervisor),
         stakers_to_create <- Albagen.Config.stakers_to_create(),
         {:ok, stakers_saved} <- Albagen.Model.Account.count_created_stakers() do
      Logger.warn(
        "OBSERVER | stakers to create = #{stakers_to_create}, stakers running = #{stakers_running}, stakers saved = #{stakers_saved}, staker tasks: #{tasks}"
      )
    else
      error ->
        Logger.error("Observer encountered error: #{inspect(error)}")
    end

    {:noreply, %{state | timer_stakers: Process.send_after(self(), :observe_stakers, 300_000)}}
  end

  def handle_info(:observe_txs, state = %{txs: 0}),
    do: {:noreply, %{state | timer_txs: Process.send_after(self(), :observe_txs, 120_000)}}

  def handle_info(:observe_txs, state = %{txs: txs, last_flush: last_flushed}) do
    now = System.os_time(:millisecond)
    time_passed_in_minutes = (now - last_flushed) / 60_000
    txs_per_minute = (txs / time_passed_in_minutes) |> round()

    Logger.warn("OBSERVER | Average txs per minute #{txs_per_minute}")

    {:noreply,
     %{
       state
       | txs: 0,
         last_flush: now,
         timer_txs: Process.send_after(self(), :observe_txs, 120_000)
     }}
  end
end
