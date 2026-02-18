defmodule Evo.TokenBudget do
  @moduledoc """
  Tracks token usage against a configurable daily budget.
  Pauses the evolution loop when the budget is exhausted.
  """

  use GenServer

  @default_daily_budget 100_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns true if there's remaining budget for API calls."
  @spec has_budget?() :: boolean()
  def has_budget? do
    GenServer.call(__MODULE__, :has_budget?)
  end

  @doc "Records token usage from an API call."
  @spec record_usage(non_neg_integer(), non_neg_integer()) :: :ok
  def record_usage(tokens_in, tokens_out) do
    GenServer.cast(__MODULE__, {:record_usage, tokens_in, tokens_out})
  end

  @doc "Returns the current budget status for observability."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Resets the daily budget (called at midnight or manually)."
  @spec reset() :: :ok
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # Server

  @impl true
  def init(opts) do
    daily_budget = Keyword.get(opts, :daily_budget, @default_daily_budget)

    state = %{
      daily_budget: daily_budget,
      tokens_used_today: 0,
      total_tokens_in: 0,
      total_tokens_out: 0,
      api_calls_today: 0,
      last_reset: Date.utc_today()
    }

    # Schedule daily reset check
    schedule_reset_check()

    {:ok, state}
  end

  @impl true
  def handle_call(:has_budget?, _from, state) do
    state = maybe_auto_reset(state)
    has_budget = state.tokens_used_today < state.daily_budget
    {:reply, has_budget, state}
  end

  def handle_call(:status, _from, state) do
    state = maybe_auto_reset(state)

    status = %{
      daily_budget: state.daily_budget,
      tokens_used_today: state.tokens_used_today,
      tokens_remaining: max(state.daily_budget - state.tokens_used_today, 0),
      total_tokens_in: state.total_tokens_in,
      total_tokens_out: state.total_tokens_out,
      api_calls_today: state.api_calls_today,
      budget_percentage_used: Float.round(state.tokens_used_today / state.daily_budget * 100, 1),
      last_reset: state.last_reset
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:record_usage, tokens_in, tokens_out}, state) do
    total = tokens_in + tokens_out

    new_state = %{
      state
      | tokens_used_today: state.tokens_used_today + total,
        total_tokens_in: state.total_tokens_in + tokens_in,
        total_tokens_out: state.total_tokens_out + tokens_out,
        api_calls_today: state.api_calls_today + 1
    }

    :telemetry.execute([:evo, :token_budget, :update], %{
      used: new_state.tokens_used_today,
      remaining: max(new_state.daily_budget - new_state.tokens_used_today, 0)
    }, %{})

    {:noreply, new_state}
  end

  def handle_cast(:reset, state) do
    {:noreply, do_reset(state)}
  end

  @impl true
  def handle_info(:check_reset, state) do
    schedule_reset_check()
    {:noreply, maybe_auto_reset(state)}
  end

  defp maybe_auto_reset(state) do
    if Date.utc_today() != state.last_reset do
      do_reset(state)
    else
      state
    end
  end

  defp do_reset(state) do
    %{state | tokens_used_today: 0, api_calls_today: 0, last_reset: Date.utc_today()}
  end

  defp schedule_reset_check do
    # Check every hour
    Process.send_after(self(), :check_reset, :timer.hours(1))
  end
end
