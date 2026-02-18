defmodule Evo.Evolvable.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Evo.Evolvable.PromptBuilder

  describe "build/3" do
    test "returns a string containing the module name" do
      result = PromptBuilder.build("MyModule", "defmodule MyModule do\nend", %{})
      assert is_binary(result)
      assert result =~ "MyModule"
    end

    test "includes the source code in the prompt" do
      source = "defmodule Foo do\n  def bar, do: :ok\nend"
      result = PromptBuilder.build("Foo", source, %{})
      assert result =~ "def bar, do: :ok"
    end

    test "includes benchmark data in the prompt" do
      benchmarks = %{execution_time_us: 42.5, memory_bytes: 1024}
      result = PromptBuilder.build("Foo", "code", benchmarks)
      assert result =~ "execution_time_us"
      assert result =~ "42.5"
    end

    test "includes safety constraints" do
      result = PromptBuilder.build("Foo", "code", %{})
      assert result =~ "System.cmd"
      assert result =~ "File.rm"
    end
  end

  describe "format_benchmarks/1" do
    test "formats a map into readable lines" do
      result = PromptBuilder.format_benchmarks(%{time: 100, memory: 200})
      assert result =~ "time"
      assert result =~ "memory"
    end

    test "handles empty map" do
      result = PromptBuilder.format_benchmarks(%{})
      assert result == ""
    end

    test "handles non-map input" do
      result = PromptBuilder.format_benchmarks(nil)
      assert result == "No benchmark data available."
    end
  end
end
