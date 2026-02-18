defmodule Evo.Evolvable.Strategy do
  @moduledoc """
  Decides which evolvable module to target next and what kind of improvement to attempt.
  This module is part of the evolvable surface — the system can modify it.
  """

  @evolvable_modules [
    Evo.Evolvable.PromptBuilder,
    Evo.Evolvable.Fitness,
    Evo.Evolvable.Strategy,
    Evo.Evolvable.CreativeDisplay
  ]

  @doc """
  Selects the next module to evolve based on generation number and history.

  Uses round-robin by default. The generation number determines which module
  is selected: gen 0 → PromptBuilder, gen 1 → Fitness, gen 2 → Strategy, etc.
  """
  @spec select_target(generation :: non_neg_integer(), history :: list()) :: module()
  def select_target(generation, _history \\ []) do
    index = rem(generation, length(@evolvable_modules))
    Enum.at(@evolvable_modules, index)
  end

  @doc """
  Returns the list of modules that are allowed to be evolved.
  """
  @spec evolvable_modules() :: [module()]
  def evolvable_modules, do: @evolvable_modules

  @doc """
  Returns the source file path for a given evolvable module.
  """
  @spec source_path(module()) :: String.t()
  def source_path(module) do
    module_name =
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    Path.join(["lib", "evo", "evolvable", "#{module_name}.ex"])
  end

  @doc """
  Returns the test file path for a given evolvable module.
  """
  @spec test_path(module()) :: String.t()
  def test_path(module) do
    module_name =
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    Path.join(["test", "evo", "evolvable", "#{module_name}_test.exs"])
  end
end
