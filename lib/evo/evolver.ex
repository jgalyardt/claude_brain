defmodule Evo.Evolver do
  @moduledoc """
  The main evolution loop GenServer.

  Orchestrates: benchmark → propose → validate → apply → record.
  Runs on a configurable interval and can be paused/resumed.
  """

  use GenServer

  require Logger

  alias Evo.{Benchmarker, Proposer, Validator, Applier, Historian, ModelRouter}
  alias Evo.Evolvable.{Fitness, Strategy}

  @default_interval_ms :timer.minutes(5)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Manually trigger a single evolution cycle."
  @spec run_once() :: {:ok, map()} | {:error, term()}
  def run_once do
    GenServer.call(__MODULE__, :run_once, :timer.minutes(5))
  end

  @doc "Pause the automatic evolution loop."
  @spec pause() :: :ok
  def pause, do: GenServer.cast(__MODULE__, :pause)

  @doc "Resume the automatic evolution loop."
  @spec resume() :: :ok
  def resume, do: GenServer.cast(__MODULE__, :resume)

  @doc "Returns the current state for observability."
  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  # Server

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    auto_start = Keyword.get(opts, :auto_start, false)

    state = %{
      generation: 0,
      interval_ms: interval,
      running: auto_start,
      last_result: nil,
      total_accepted: 0,
      total_rejected: 0,
      timer_ref: nil
    }

    state =
      if auto_start do
        schedule_next(state)
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:run_once, _from, state) do
    {result, new_state} = execute_cycle(state)
    {:reply, result, new_state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      generation: state.generation,
      running: state.running,
      interval_ms: state.interval_ms,
      last_result: state.last_result,
      total_accepted: state.total_accepted,
      total_rejected: state.total_rejected,
      accept_rate: accept_rate(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:pause, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    Logger.info("[Evo] Evolution loop paused at generation #{state.generation}")
    {:noreply, %{state | running: false, timer_ref: nil}}
  end

  def handle_cast(:resume, state) do
    Logger.info("[Evo] Evolution loop resumed at generation #{state.generation}")
    new_state = %{state | running: true} |> schedule_next()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:evolve, %{running: false} = state) do
    {:noreply, state}
  end

  def handle_info(:evolve, state) do
    {_result, new_state} = execute_cycle(state)
    new_state = schedule_next(new_state)
    {:noreply, new_state}
  end

  # Core evolution cycle

  defp execute_cycle(state) do
    generation = state.generation
    :telemetry.execute([:evo, :generation, :start], %{generation: generation}, %{})

    Logger.info("[Evo] Starting generation #{generation}")

    target_module = Strategy.select_target(generation)
    Logger.info("[Evo] Target module: #{inspect(target_module)}")

    result = do_evolve(target_module, generation)

    new_state =
      case result do
        {:ok, gen_record} ->
          Logger.info("[Evo] Generation #{generation} completed: #{gen_record.status}")

          %{
            state
            | generation: generation + 1,
              last_result: gen_record,
              total_accepted: state.total_accepted + if(gen_record.status == "accepted", do: 1, else: 0),
              total_rejected: state.total_rejected + if(gen_record.status != "accepted", do: 1, else: 0)
          }

        {:error, reason} ->
          Logger.warning("[Evo] Generation #{generation} failed: #{inspect(reason)}")

          %{
            state
            | generation: generation + 1,
              last_result: %{status: "error", reason: reason},
              total_rejected: state.total_rejected + 1
          }
      end

    :telemetry.execute([:evo, :generation, :complete], %{
      generation: generation,
      duration: 0
    }, %{accepted: match?({:ok, %{status: "accepted"}}, result)})

    {result, new_state}
  end

  defp do_evolve(target_module, generation) do
    with {:ok, before_benchmarks} <- Benchmarker.run(target_module),
         {:ok, proposal} <- Proposer.propose(target_module, before_benchmarks),
         :ok <- Validator.validate(proposal),
         {:ok, :applied} <- Applier.apply_proposal(proposal),
         {:ok, after_benchmarks} <- Benchmarker.run(target_module) do
      {verdict, score} = Fitness.evaluate(before_benchmarks, after_benchmarks)

      {status, score} =
        case verdict do
          :improved ->
            ModelRouter.report_success()
            {"accepted", score}

          :neutral ->
            # Accept neutral changes (they might be clarity improvements)
            ModelRouter.report_success()
            {"accepted_neutral", score}

          :regressed ->
            # Rollback
            Applier.rollback(proposal)
            ModelRouter.report_failure()
            {"rejected_regression", score}
        end

      gen_attrs = %{
        generation_number: generation,
        target_module: inspect(target_module),
        status: status,
        fitness_score: score,
        model_used: proposal.model_used,
        tokens_in: proposal.tokens_in,
        tokens_out: proposal.tokens_out,
        reasoning: proposal.reasoning,
        old_code: proposal.old_code,
        new_code: proposal.new_code
      }

      Historian.record_generation(gen_attrs)
    else
      {:error, reason} ->
        ModelRouter.report_failure()

        gen_attrs = %{
          generation_number: generation,
          target_module: inspect(target_module),
          status: "error",
          fitness_score: 0.0,
          model_used: ModelRouter.current_model(),
          tokens_in: 0,
          tokens_out: 0,
          reasoning: inspect(reason)
        }

        Historian.record_generation(gen_attrs)
        {:error, reason}
    end
  end

  defp schedule_next(state) do
    ref = Process.send_after(self(), :evolve, state.interval_ms)
    %{state | timer_ref: ref}
  end

  defp accept_rate(%{total_accepted: 0, total_rejected: 0}), do: 0.0

  defp accept_rate(state) do
    total = state.total_accepted + state.total_rejected
    Float.round(state.total_accepted / total * 100, 1)
  end
end
