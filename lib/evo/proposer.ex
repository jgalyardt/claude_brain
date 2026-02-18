defmodule Evo.Proposer do
  @moduledoc """
  Sends code + benchmarks to Claude and parses the response into a proposal.
  """

  alias Evo.Evolvable.{PromptBuilder, Strategy}
  alias Evo.{ModelRouter, TokenBudget}

  defstruct [:module, :old_code, :new_code, :reasoning, :model_used, :tokens_in, :tokens_out]

  @type t :: %__MODULE__{
          module: module(),
          old_code: String.t(),
          new_code: String.t(),
          reasoning: String.t(),
          model_used: String.t(),
          tokens_in: non_neg_integer(),
          tokens_out: non_neg_integer()
        }

  @doc """
  Proposes an improvement for the given module.

  Reads the module source, builds a prompt, calls Claude, and parses the response.
  """
  @spec propose(module(), map()) :: {:ok, t()} | {:error, term()}
  def propose(module, benchmarks) do
    with {:ok, source} <- read_source(module),
         {:budget, true} <- {:budget, TokenBudget.has_budget?()},
         model <- ModelRouter.current_model(),
         module_name <- inspect(module),
         prompt <- PromptBuilder.build(module_name, source, benchmarks),
         {:ok, response} <- call_claude(prompt, model),
         {:ok, proposal} <- parse_response(response, module, source, model) do
      :telemetry.execute([:evo, :proposal, :complete], %{
        tokens_in: proposal.tokens_in,
        tokens_out: proposal.tokens_out
      }, %{model: model})

      TokenBudget.record_usage(proposal.tokens_in, proposal.tokens_out)
      {:ok, proposal}
    else
      {:budget, false} -> {:error, :budget_exhausted}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_source(module) do
    path = Strategy.source_path(module)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  defp call_claude(prompt, model) do
    api_key = Application.get_env(:evo, :anthropic_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body = %{
        model: model,
        max_tokens: 4096,
        messages: [
          %{role: "user", content: prompt}
        ]
      }

      case Req.post("https://api.anthropic.com/v1/messages",
             json: body,
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"},
               {"content-type", "application/json"}
             ],
             receive_timeout: 60_000
           ) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp parse_response(response, module, old_code, model) do
    content =
      response
      |> Map.get("content", [])
      |> Enum.find(%{}, fn block -> block["type"] == "text" end)
      |> Map.get("text", "")

    usage = Map.get(response, "usage", %{})
    tokens_in = Map.get(usage, "input_tokens", 0)
    tokens_out = Map.get(usage, "output_tokens", 0)

    case extract_code(content) do
      {:ok, new_code} ->
        reasoning = extract_reasoning(content)

        proposal = %__MODULE__{
          module: module,
          old_code: old_code,
          new_code: new_code,
          reasoning: reasoning,
          model_used: model,
          tokens_in: tokens_in,
          tokens_out: tokens_out
        }

        {:ok, proposal}

      :error ->
        {:error, :no_code_in_response}
    end
  end

  defp extract_code(text) do
    case Regex.run(~r/```elixir\n(.*?)```/s, text) do
      [_, code] -> {:ok, String.trim(code)}
      _ -> :error
    end
  end

  defp extract_reasoning(text) do
    case Regex.run(~r/## Reasoning:?\s*(.+)/s, text) do
      [_, reasoning] -> String.trim(reasoning)
      _ -> "No reasoning provided."
    end
  end
end
