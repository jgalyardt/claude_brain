defmodule Evo.Evolvable.CreativeDisplayTest do
  use ExUnit.Case, async: true

  alias Evo.Evolvable.CreativeDisplay

  describe "render/1" do
    test "returns a binary string" do
      result = CreativeDisplay.render(%{})
      assert is_binary(result)
    end

    test "handles empty stats map" do
      result = CreativeDisplay.render(%{})
      assert String.contains?(result, "GEN 0")
    end

    test "incorporates generation number" do
      result = CreativeDisplay.render(%{generation: 42})
      assert String.contains?(result, "GEN 42")
    end

    test "handles typical stats" do
      stats = %{generation: 10, accept_rate: 50, budget_used: 30}
      result = CreativeDisplay.render(stats)
      assert is_binary(result)
      assert String.contains?(result, "svg")
    end

    test "returns valid HTML with SVG" do
      result = CreativeDisplay.render(%{generation: 5})
      assert String.contains?(result, "<svg")
      assert String.contains?(result, "</svg>")
    end
  end
end
