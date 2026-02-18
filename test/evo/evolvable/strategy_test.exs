defmodule Evo.Evolvable.StrategyTest do
  use ExUnit.Case, async: true

  alias Evo.Evolvable.Strategy

  describe "select_target/2" do
    test "cycles through modules based on generation" do
      modules = Strategy.evolvable_modules()

      Enum.each(0..(length(modules) - 1), fn gen ->
        target = Strategy.select_target(gen)
        assert target == Enum.at(modules, gen)
      end)
    end

    test "wraps around after all modules" do
      modules = Strategy.evolvable_modules()
      count = length(modules)

      assert Strategy.select_target(0) == Strategy.select_target(count)
      assert Strategy.select_target(1) == Strategy.select_target(count + 1)
    end
  end

  describe "evolvable_modules/0" do
    test "returns a non-empty list of modules" do
      modules = Strategy.evolvable_modules()
      assert is_list(modules)
      assert length(modules) > 0

      Enum.each(modules, fn mod ->
        assert is_atom(mod)
      end)
    end

    test "includes the three core evolvable modules" do
      modules = Strategy.evolvable_modules()
      assert Evo.Evolvable.PromptBuilder in modules
      assert Evo.Evolvable.Fitness in modules
      assert Evo.Evolvable.Strategy in modules
    end
  end

  describe "source_path/1" do
    test "returns correct path for PromptBuilder" do
      path = Strategy.source_path(Evo.Evolvable.PromptBuilder)
      assert path =~ "prompt_builder.ex"
      assert path =~ "evolvable"
    end

    test "returns correct path for Fitness" do
      path = Strategy.source_path(Evo.Evolvable.Fitness)
      assert path =~ "fitness.ex"
    end
  end

  describe "test_path/1" do
    test "returns correct path for PromptBuilder" do
      path = Strategy.test_path(Evo.Evolvable.PromptBuilder)
      assert path =~ "prompt_builder_test.exs"
      assert path =~ "test"
    end
  end
end
