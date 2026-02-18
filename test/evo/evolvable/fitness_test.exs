defmodule Evo.Evolvable.FitnessTest do
  use ExUnit.Case, async: true

  alias Evo.Evolvable.Fitness

  describe "evaluate/2" do
    test "detects improvement when metrics decrease" do
      before = %{execution_time_us: 100, memory_bytes: 1000, code_size_lines: 50}
      after_b = %{execution_time_us: 80, memory_bytes: 800, code_size_lines: 45}

      assert {:improved, score} = Fitness.evaluate(before, after_b)
      assert score > 0
    end

    test "detects regression when metrics increase" do
      before = %{execution_time_us: 100, memory_bytes: 1000, code_size_lines: 50}
      after_b = %{execution_time_us: 150, memory_bytes: 1500, code_size_lines: 60}

      assert {:regressed, score} = Fitness.evaluate(before, after_b)
      assert score < 0
    end

    test "returns neutral for negligible changes" do
      before = %{execution_time_us: 100, memory_bytes: 1000, code_size_lines: 50}
      after_b = %{execution_time_us: 99, memory_bytes: 998, code_size_lines: 50}

      assert {:neutral, +0.0} = Fitness.evaluate(before, after_b)
    end
  end

  describe "compute_score/2" do
    test "returns positive score for improvements" do
      before = %{execution_time_us: 100, memory_bytes: 1000, code_size_lines: 50}
      after_b = %{execution_time_us: 50, memory_bytes: 500, code_size_lines: 40}

      score = Fitness.compute_score(before, after_b)
      assert score > 0
    end

    test "handles zero values gracefully" do
      before = %{execution_time_us: 0, memory_bytes: 0, code_size_lines: 0}
      after_b = %{execution_time_us: 10, memory_bytes: 100, code_size_lines: 5}

      score = Fitness.compute_score(before, after_b)
      assert score == 0.0
    end

    test "handles missing keys" do
      score = Fitness.compute_score(%{}, %{})
      assert score == 0.0
    end
  end

  describe "regression_threshold/0" do
    test "returns a negative float" do
      assert Fitness.regression_threshold() < 0
    end
  end
end
