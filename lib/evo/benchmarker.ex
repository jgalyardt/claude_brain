defmodule Evo.Benchmarker do
  @moduledoc """
  Runs microbenchmarks on evolvable modules and returns structured results.
  Uses Benchee for timing and measures code size directly.
  """

  alias Evo.Evolvable.Strategy

  @doc """
  Benchmarks a specific evolvable module.

  Returns a map with keys:
  - :execution_time_us - average execution time in microseconds
  - :memory_bytes - average memory usage in bytes
  - :code_size_lines - number of lines in the source file
  """
  @spec run(module()) :: {:ok, map()} | {:error, term()}
  def run(module) do
    with {:ok, source} <- read_source(module),
         {:ok, timing} <- measure_timing(module),
         {:ok, memory} <- measure_memory(module) do
      result = %{
        execution_time_us: timing,
        memory_bytes: memory,
        code_size_lines: count_lines(source),
        measured_at: DateTime.utc_now()
      }

      :telemetry.execute([:evo, :benchmark, :complete], result, %{module: module})
      {:ok, result}
    end
  end

  @doc """
  Benchmarks all evolvable modules and returns a map of module => results.
  """
  @spec run_all() :: %{module() => map()}
  def run_all do
    Strategy.evolvable_modules()
    |> Enum.map(fn mod ->
      case run(mod) do
        {:ok, result} -> {mod, result}
        {:error, _} -> {mod, %{}}
      end
    end)
    |> Map.new()
  end

  defp read_source(module) do
    path = Strategy.source_path(module)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  defp measure_timing(module) do
    # Use a representative function call for benchmarking
    {fun, args} = benchmark_function(module)

    # Run multiple iterations and take the average
    times =
      for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fun, args)
        time_us
      end

    avg = Enum.sum(times) / length(times)
    {:ok, avg}
  rescue
    e -> {:error, {:benchmark_failed, module, e}}
  end

  defp measure_memory(module) do
    {fun, args} = benchmark_function(module)

    # Measure memory by checking process heap before/after
    :erlang.garbage_collect()
    {_, before_mem} = Process.info(self(), :memory)

    apply(fun, args)

    :erlang.garbage_collect()
    {_, after_mem} = Process.info(self(), :memory)

    {:ok, max(after_mem - before_mem, 0)}
  rescue
    e -> {:error, {:memory_measure_failed, module, e}}
  end

  defp count_lines(source) do
    source |> String.split("\n") |> length()
  end

  # Define representative benchmark functions for each evolvable module
  defp benchmark_function(Evo.Evolvable.PromptBuilder) do
    {fn -> Evo.Evolvable.PromptBuilder.build("TestModule", "defmodule T do\nend", %{time: 100}) end, []}
  end

  defp benchmark_function(Evo.Evolvable.Fitness) do
    before = %{execution_time_us: 100, memory_bytes: 1000, code_size_lines: 50}
    after_b = %{execution_time_us: 80, memory_bytes: 800, code_size_lines: 45}
    {fn -> Evo.Evolvable.Fitness.evaluate(before, after_b) end, []}
  end

  defp benchmark_function(Evo.Evolvable.Strategy) do
    {fn -> Evo.Evolvable.Strategy.select_target(0) end, []}
  end

  defp benchmark_function(_module) do
    {fn -> :ok end, []}
  end
end
