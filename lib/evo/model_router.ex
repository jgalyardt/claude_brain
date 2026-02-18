defmodule Evo.ModelRouter do
  @moduledoc """
  Manages model selection between Haiku and Sonnet.

  Starts with Haiku. After consecutive failures, escalates to Sonnet.
  Drops back to Haiku after a Sonnet success.
  """

  use GenServer

  @haiku "claude-haiku-4-5-20251001"
  @sonnet "claude-sonnet-4-5-20250929"
  @escalation_threshold 3

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current model ID to use."
  @spec current_model() :: String.t()
  def current_model do
    GenServer.call(__MODULE__, :current_model)
  end

  @doc "Report a successful proposal — resets failure count, drops to Haiku."
  @spec report_success() :: :ok
  def report_success do
    GenServer.cast(__MODULE__, :success)
  end

  @doc "Report a failed proposal — increments failure count, may escalate."
  @spec report_failure() :: :ok
  def report_failure do
    GenServer.cast(__MODULE__, :failure)
  end

  @doc "Returns the current state for observability."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # Server

  @impl true
  def init(_opts) do
    state = %{
      current_model: :haiku,
      consecutive_failures: 0,
      total_haiku_calls: 0,
      total_sonnet_calls: 0,
      escalations: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:current_model, _from, state) do
    model_id = model_id(state.current_model)
    {:reply, model_id, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:success, state) do
    new_state =
      state
      |> Map.put(:consecutive_failures, 0)
      |> increment_call_count()
      |> Map.put(:current_model, :haiku)

    if state.current_model != :haiku do
      :telemetry.execute([:evo, :model_switch], %{}, %{
        from: state.current_model,
        to: :haiku,
        reason: :success_deescalation
      })
    end

    {:noreply, new_state}
  end

  def handle_cast(:failure, state) do
    new_failures = state.consecutive_failures + 1
    new_state = %{state | consecutive_failures: new_failures}

    new_state =
      if new_failures >= @escalation_threshold and state.current_model == :haiku do
        :telemetry.execute([:evo, :model_switch], %{}, %{
          from: :haiku,
          to: :sonnet,
          reason: :failure_escalation
        })

        %{new_state | current_model: :sonnet, escalations: new_state.escalations + 1}
      else
        new_state
      end

    {:noreply, increment_call_count(new_state)}
  end

  defp increment_call_count(%{current_model: :haiku} = state) do
    %{state | total_haiku_calls: state.total_haiku_calls + 1}
  end

  defp increment_call_count(%{current_model: :sonnet} = state) do
    %{state | total_sonnet_calls: state.total_sonnet_calls + 1}
  end

  defp model_id(:haiku), do: @haiku
  defp model_id(:sonnet), do: @sonnet
end
