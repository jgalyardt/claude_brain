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

    creative_html =
      try do
        Evo.Evolvable.CreativeDisplay.render(%{
          generation: evolver_status.generation,
          accept_rate: evolver_status.accept_rate,
          budget_used: budget_status.budget_percentage_used
        })
      rescue
        _ -> "<div style='color: red; padding: 20px;'>CreativeDisplay render failed</div>"
      end

    socket
    |> assign(:evolver, evolver_status)
    |> assign(:model, model_status)
    |> assign(:budget, budget_status)
    |> assign(:generations, generations)
    |> assign(:creative_html, creative_html)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-base-content tracking-tight">Evolution Dashboard</h1>
          <p class="text-sm text-base-content/50 font-mono">generation #{@evolver.generation}</p>
        </div>
        <div class="flex gap-3 items-center">
          <%= if @evolver.running do %>
            <button phx-click="pause" class="btn btn-warning btn-sm">Pause</button>
          <% else %>
            <button phx-click="resume" class="btn btn-success btn-sm">Resume</button>
          <% end %>
          <button phx-click="run_once" class="btn btn-primary btn-sm">Run Once</button>
          <span class={"badge #{if @evolver.running, do: "badge-success", else: "badge-neutral"} badge-sm gap-1"}>
            <span class={"inline-block w-1.5 h-1.5 rounded-full #{if @evolver.running, do: "bg-success-content animate-pulse", else: "bg-neutral-content"}"} />
            <%= if @evolver.running, do: "Running", else: "Paused" %>
          </span>
        </div>
      </div>

      <!-- Creative Display — evolved by Claude -->
      <div class="rounded-box overflow-hidden shadow-lg">
        <%= Phoenix.HTML.raw(@creative_html) %>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <.stat_card title="Generation" value={@evolver.generation} />
        <.stat_card title="Accept Rate" value={"#{@evolver.accept_rate}%"} />
        <.stat_card title="Model" value={@model.current_model} />
        <.stat_card title="Budget Used" value={"#{@budget.budget_percentage_used}%"} />
      </div>

      <!-- Model & Budget Details -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-5">
            <h2 class="card-title text-sm font-semibold text-base-content/70 uppercase tracking-wider">Model Usage</h2>
            <div class="space-y-2 mt-2">
              <.detail_row label="Haiku calls" value={@model.total_haiku_calls} />
              <.detail_row label="Sonnet calls" value={@model.total_sonnet_calls} />
              <.detail_row label="Consecutive failures" value={@model.consecutive_failures} />
              <.detail_row label="Escalations" value={@model.escalations} />
            </div>
          </div>
        </div>

        <div class="card bg-base-200 shadow-sm">
          <div class="card-body p-5">
            <h2 class="card-title text-sm font-semibold text-base-content/70 uppercase tracking-wider">Token Budget</h2>
            <div class="w-full bg-base-300 rounded-full h-2.5 mt-3 mb-3">
              <div
                class={"h-2.5 rounded-full transition-all duration-500 #{if @budget.budget_percentage_used > 80, do: "bg-error", else: "bg-primary"}"}
                style={"width: #{min(@budget.budget_percentage_used, 100)}%"}
              />
            </div>
            <div class="space-y-2">
              <.detail_row label="Used today" value={"#{@budget.tokens_used_today} / #{@budget.daily_budget}"} />
              <.detail_row label="API calls today" value={@budget.api_calls_today} />
              <.detail_row label="Total in" value={@budget.total_tokens_in} />
              <.detail_row label="Total out" value={@budget.total_tokens_out} />
            </div>
          </div>
        </div>
      </div>

      <!-- Generation History -->
      <div class="card bg-base-200 shadow-sm">
        <div class="card-body p-5">
          <h2 class="card-title text-sm font-semibold text-base-content/70 uppercase tracking-wider">Evolution History</h2>
          <div class="overflow-x-auto mt-2">
            <table class="table table-sm">
              <thead>
                <tr class="text-base-content/50">
                  <th>Gen</th>
                  <th>Module</th>
                  <th>Status</th>
                  <th>Score</th>
                  <th>Model</th>
                  <th>Tokens</th>
                  <th>Reasoning</th>
                </tr>
              </thead>
              <tbody>
                <%= for gen <- @generations do %>
                  <tr class="hover">
                    <td class="font-mono text-sm"><%= gen.generation_number %></td>
                    <td class="text-sm"><%= short_module(gen.target_module) %></td>
                    <td>
                      <span class={"badge badge-sm #{status_badge(gen.status)}"}>
                        <%= gen.status %>
                      </span>
                    </td>
                    <td class="font-mono text-sm"><%= Float.round(gen.fitness_score || 0.0, 4) %></td>
                    <td class="text-sm"><%= short_model(gen.model_used) %></td>
                    <td class="font-mono text-sm"><%= (gen.tokens_in || 0) + (gen.tokens_out || 0) %></td>
                    <td class="text-sm text-base-content/60 truncate max-w-xs"><%= gen.reasoning %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Components

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-sm">
      <div class="card-body p-4">
        <div class="text-xs font-semibold text-base-content/50 uppercase tracking-wider"><%= @title %></div>
        <div class="text-xl font-bold text-base-content mt-1 font-mono"><%= @value %></div>
      </div>
    </div>
    """
  end

  defp detail_row(assigns) do
    ~H"""
    <div class="flex justify-between items-center">
      <span class="text-sm text-base-content/60"><%= @label %></span>
      <span class="font-mono text-sm text-base-content"><%= @value %></span>
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

  defp status_badge("accepted"), do: "badge-success"
  defp status_badge("accepted_neutral"), do: "badge-info"
  defp status_badge("rejected_regression"), do: "badge-error"
  defp status_badge("rejected_validation"), do: "badge-warning"
  defp status_badge("error"), do: "badge-error"
  defp status_badge(_), do: "badge-neutral"
end
