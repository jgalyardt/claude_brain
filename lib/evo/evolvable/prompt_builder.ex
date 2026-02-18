defmodule Evo.Evolvable.PromptBuilder do
  @moduledoc """
  Constructs prompts sent to Claude for code improvement proposals.
  This module is part of the evolvable surface — the system can modify it.
  """

  @doc """
  Builds a prompt asking Claude to propose an improvement to the given module.

  Returns a string prompt suitable for the Claude Messages API.
  """
  @spec build(module :: String.t(), source :: String.t(), benchmarks :: map()) :: String.t()
  def build(module_name, source_code, benchmarks) do
    """
    You are an Elixir code optimizer. Your task is to propose a single, focused improvement
    to the following Elixir module.

    ## Module: #{module_name}

    ```elixir
    #{source_code}
    ```

    ## Current Benchmark Results
    #{format_benchmarks(benchmarks)}

    ## Constraints
    - You MUST return the complete, modified module source code
    - The module name and public API (function names, arities) must remain the same
    - Do NOT use: System.cmd, File.rm, Code.eval_string, Port.open, or any network calls
    - Focus on ONE improvement: performance, clarity, or correctness
    - Keep the change small (under 50 lines changed)

    ## Response Format
    Return ONLY the improved module source code wrapped in ```elixir``` code fences.
    After the code block, add a one-line "## Reasoning:" section explaining your change.
    """
  end

  @doc """
  Formats benchmark results into a human-readable string for prompt inclusion.
  """
  @spec format_benchmarks(map()) :: String.t()
  def format_benchmarks(benchmarks) when is_map(benchmarks) do
    benchmarks
    |> Enum.map(fn {key, value} -> "- #{key}: #{inspect(value)}" end)
    |> Enum.join("\n")
  end

  def format_benchmarks(_), do: "No benchmark data available."
end
