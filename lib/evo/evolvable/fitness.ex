defmodule Evo.Evolvable.Fitness do
  @moduledoc """
  Evaluates whether a proposed change is an improvement over the current code.
  This module is part of the evolvable surface — the system can modify it.
  """

  @doc """
  Compares before/after benchmark results and returns a fitness score.

  Returns `{:improved, score}` if the change is beneficial,
  `{:regressed, score}` if it made things worse,
  or `{:neutral, 0.0}` if no meaningful change.

  Score is a float where positive = better, negative = worse.
  """
  @spec evaluate(before :: map(), after_benchmarks :: map()) ::
          {:improved, float()} | {:regressed, float()} | {:neutral, float()}
  def evaluate(before, after_benchmarks) do
    score = compute_score(before, after_benchmarks)

    cond do
      score > 0.05 -> {:improved, score}
      score < -0.05 -> {:regressed, score}
      true -> {:neutral, 0.0}
    end
  end

  @doc """
  Computes a weighted score comparing before/after metrics.

  Metrics compared:
  - execution_time_us: lower is better (weight: 0.6)
  - memory_bytes: lower is better (weight: 0.3)
  - code_size_lines: lower is better (weight: 0.1)
  """
  @spec compute_score(map(), map()) :: float()
  def compute_score(before, after_benchmarks) do
    weights = %{
      execution_time_us: 0.6,
      memory_bytes: 0.3,
      code_size_lines: 0.1
    }

    weights
    |> Enum.map(fn {metric, weight} ->
      before_val = Map.get(before, metric, 0)
      after_val = Map.get(after_benchmarks, metric, 0)

      if before_val > 0 do
        improvement_ratio = (before_val - after_val) / before_val
        improvement_ratio * weight
      else
        0.0
      end
    end)
    |> Enum.sum()
  end

  @doc """
  Returns the threshold below which a regression is unacceptable.
  """
  @spec regression_threshold() :: float()
  def regression_threshold, do: -0.10
end
