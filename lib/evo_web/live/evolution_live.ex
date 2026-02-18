defmodule EvoWeb.EvolutionLive do
  @moduledoc """
  LiveView dashboard for observing the evolution system.
  Shows generation history, benchmarks, model usage, and token budget.
  """

  use EvoWeb, :live_view

  alias Evo.{Evolver, ModelRouter, TokenBudget, Historian}

  # Minimum seconds between manual run_once triggers
  @run_once_cooldown_ms :timer.seconds(30)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Evo.PubSub, "evo:updates")
      :timer.send_interval(10_000, self(), :refresh)
    end

    socket =
      socket
      |> assign(:page_title, "Evolution Dashboard")
      |> assign(:last_run_once, 0)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("pause", _params, socket) do
    Evolver.pause()
    {:noreply, load_data(socket)}
  end

  def handle_event("resume", _params, socket) do
    Evolver.resume()
    {:noreply, load_data(socket)}
  end

  def handle_event("run_once", _params, socket) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - socket.assigns.last_run_once

    if elapsed >= @run_once_cooldown_ms do
      Task.start(fn -> Evolver.run_once() end)
      {:noreply, socket |> assign(:last_run_once, now) |> put_flash(:info, "Evolution cycle triggered...")}
    else
      remaining = div(@run_once_cooldown_ms - elapsed, 1000)
      {:noreply, put_flash(socket, :error, "Rate limited. Wait #{remaining}s.")}
    end
  end

  defp load_data(socket) do
    evolver_status = Evolver.status()
    model_status = ModelRouter.status()
    budget_status = TokenBudget.status()
    generations = Historian.recent_generations(50)

    socket
    |> assign(:evolver, evolver_status)
    |> assign(:model, model_status)
    |> assign(:budget, budget_status)
    |> assign(:generations, generations)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto p-6 space-y-6">
      <h1 class="text-3xl font-bold text-gray-900">Evo: Evolution Dashboard</h1>

      <!-- Controls -->
      <div class="flex gap-4 items-center">
        <%= if @evolver.running do %>
          <button phx-click="pause" class="bg-yellow-500 hover:bg-yellow-600 text-white px-4 py-2 rounded font-medium">
            Pause
          </button>
        <% else %>
          <button phx-click="resume" class="bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded font-medium">
            Resume
          </button>
        <% end %>
        <button phx-click="run_once" class="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded font-medium">
          Run Once
        </button>
        <span class={"inline-flex items-center px-3 py-1 rounded-full text-sm font-medium #{if @evolver.running, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
          <%= if @evolver.running, do: "Running", else: "Paused" %>
        </span>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.stat_card title="Generation" value={@evolver.generation} />
        <.stat_card title="Accept Rate" value={"#{@evolver.accept_rate}%"} />
        <.stat_card title="Model" value={@model.current_model} />
        <.stat_card title="Budget Used" value={"#{@budget.budget_percentage_used}%"} />
      </div>

      <!-- Model & Budget Details -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <!-- Model Usage -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">Model Usage</h2>
          <div class="space-y-2">
            <div class="flex justify-between">
              <span>Haiku calls:</span>
              <span class="font-mono"><%= @model.total_haiku_calls %></span>
            </div>
            <div class="flex justify-between">
              <span>Sonnet calls:</span>
              <span class="font-mono"><%= @model.total_sonnet_calls %></span>
            </div>
            <div class="flex justify-between">
              <span>Consecutive failures:</span>
              <span class="font-mono"><%= @model.consecutive_failures %></span>
            </div>
            <div class="flex justify-between">
              <span>Escalations:</span>
              <span class="font-mono"><%= @model.escalations %></span>
            </div>
          </div>
        </div>

        <!-- Token Budget -->
        <div class="bg-white rounded-lg shadow p-6">
          <h2 class="text-lg font-semibold mb-4">Token Budget</h2>
          <div class="w-full bg-gray-200 rounded-full h-4 mb-4">
            <div
              class={"h-4 rounded-full #{if @budget.budget_percentage_used > 80, do: "bg-red-500", else: "bg-blue-500"}"}
              style={"width: #{min(@budget.budget_percentage_used, 100)}%"}
            />
          </div>
          <div class="space-y-2">
            <div class="flex justify-between">
              <span>Used today:</span>
              <span class="font-mono"><%= @budget.tokens_used_today %> / <%= @budget.daily_budget %></span>
            </div>
            <div class="flex justify-between">
              <span>API calls today:</span>
              <span class="font-mono"><%= @budget.api_calls_today %></span>
            </div>
            <div class="flex justify-between">
              <span>Total in:</span>
              <span class="font-mono"><%= @budget.total_tokens_in %></span>
            </div>
            <div class="flex justify-between">
              <span>Total out:</span>
              <span class="font-mono"><%= @budget.total_tokens_out %></span>
            </div>
          </div>
        </div>
      </div>

      <!-- Generation History -->
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Evolution History</h2>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead>
              <tr class="text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <th class="px-4 py-2">Gen</th>
                <th class="px-4 py-2">Module</th>
                <th class="px-4 py-2">Status</th>
                <th class="px-4 py-2">Score</th>
                <th class="px-4 py-2">Model</th>
                <th class="px-4 py-2">Tokens</th>
                <th class="px-4 py-2">Reasoning</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <%= for gen <- @generations do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-4 py-2 font-mono text-sm"><%= gen.generation_number %></td>
                  <td class="px-4 py-2 text-sm"><%= short_module(gen.target_module) %></td>
                  <td class="px-4 py-2">
                    <span class={"inline-flex px-2 py-1 rounded-full text-xs font-medium #{status_color(gen.status)}"}>
                      <%= gen.status %>
                    </span>
                  </td>
                  <td class="px-4 py-2 font-mono text-sm"><%= Float.round(gen.fitness_score || 0.0, 4) %></td>
                  <td class="px-4 py-2 text-sm"><%= short_model(gen.model_used) %></td>
                  <td class="px-4 py-2 font-mono text-sm"><%= (gen.tokens_in || 0) + (gen.tokens_out || 0) %></td>
                  <td class="px-4 py-2 text-sm text-gray-600 truncate max-w-xs"><%= gen.reasoning %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Components

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-4">
      <div class="text-sm text-gray-500"><%= @title %></div>
      <div class="text-2xl font-bold text-gray-900 mt-1"><%= @value %></div>
    </div>
    """
  end

  # Helpers

  defp short_module(nil), do: "-"
  defp short_module(name), do: name |> String.split(".") |> List.last()

  defp short_model(nil), do: "-"
  defp short_model(model) when is_binary(model) do
    cond do
      model =~ "haiku" -> "Haiku"
      model =~ "sonnet" -> "Sonnet"
      true -> model
    end
  end

  defp status_color("accepted"), do: "bg-green-100 text-green-800"
  defp status_color("accepted_neutral"), do: "bg-blue-100 text-blue-800"
  defp status_color("rejected_regression"), do: "bg-red-100 text-red-800"
  defp status_color("rejected_validation"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("error"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
