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
    - Focus on ONE small, surgical improvement: performance, clarity, or correctness
    - CRITICAL SIZE LIMIT: Your change is validated by counting (1) the absolute difference
      in total line count between old and new code PLUS (2) every line whose content differs.
      The total must be <= #{max_changed_lines(source_code)}. The current module is #{line_count(source_code)} lines.
      Make the SMALLEST possible change. Prefer modifying 2-5 lines over rewriting sections.
      If your improvement requires more than #{max_changed_lines(source_code)} changed lines, pick a smaller improvement.

    ## Examples of Good Changes (pick ONE per proposal)
    - Replace `Enum.map(...) |> Enum.join(...)` with `Enum.map_join/3` (1-2 lines)
    - Extract duplicated logic into a shared private function (3-5 lines)
    - Replace a multi-line `if/else` with a one-line ternary `if/do/else` form
    - Add a guard clause or pattern match to eliminate a branch
    - Use `Enum.reduce/3` instead of `Enum.map/2` + `Enum.sum/1`
    - Inline a single-use private function for clarity

    ## For CreativeDisplay: Visual/UI Changes Are Welcome
    If this module is CreativeDisplay, prioritize VISUAL creativity:
    - Add or modify SVG elements (circles, paths, polygons, gradients)
    - Add CSS animations or keyframe effects
    - Change color schemes, gradients, or hue calculations
    - Use the stats data creatively to drive visual output
    - Add text effects, glow, or shadow filters
    - Keep it fun and surprising — this is the creative playground

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

  defp max_changed_lines(source) do
    line_count = source |> String.split("\n") |> length()
    Evo.Validator.max_changed_lines(line_count)
  end

  defp line_count(source) do
    source |> String.split("\n") |> length()
  end
end
