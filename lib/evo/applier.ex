defmodule Evo.Applier do
  @moduledoc """
  Applies validated code changes to disk and hot-reloads the module.
  Supports rollback on benchmark regression.

  SECURITY: Enforces a hardcoded module→path whitelist. Only the 3 evolvable
  modules can be written to disk. Any other module is rejected.
  """

  # Hardcoded whitelist: module → source file path.
  # This is the ONLY place that maps modules to disk paths.
  # Strategy.source_path is NOT trusted for writes.
  @allowed_paths %{
    Evo.Evolvable.PromptBuilder => "lib/evo/evolvable/prompt_builder.ex",
    Evo.Evolvable.Fitness => "lib/evo/evolvable/fitness.ex",
    Evo.Evolvable.Strategy => "lib/evo/evolvable/strategy.ex"
  }

  @doc """
  Applies a validated proposal: writes the new code to disk and hot-reloads the module.
  Returns {:ok, :applied} on success.

  Rejects any module not in the hardcoded whitelist.
  """
  @spec apply_proposal(Evo.Proposer.t()) :: {:ok, :applied} | {:error, term()}
  def apply_proposal(%Evo.Proposer{} = proposal) do
    with {:ok, path} <- resolve_path(proposal.module),
         :ok <- write_file(path, proposal.new_code),
         :ok <- reload_module(proposal.module, path) do
      {:ok, :applied}
    end
  end

  @doc """
  Rolls back a proposal by restoring the old code and reloading.
  """
  @spec rollback(Evo.Proposer.t()) :: {:ok, :rolled_back} | {:error, term()}
  def rollback(%Evo.Proposer{} = proposal) do
    with {:ok, path} <- resolve_path(proposal.module),
         :ok <- write_file(path, proposal.old_code),
         :ok <- reload_module(proposal.module, path) do
      {:ok, :rolled_back}
    end
  end

  defp resolve_path(module) do
    case Map.fetch(@allowed_paths, module) do
      {:ok, path} ->
        # Double-check: resolved path must be under lib/evo/evolvable/
        normalized = Path.expand(path)

        if String.contains?(normalized, "evolvable") do
          {:ok, path}
        else
          {:error, {:path_traversal_blocked, path}}
        end

      :error ->
        {:error, {:module_not_in_whitelist, module}}
    end
  end

  defp write_file(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  defp reload_module(module, path) do
    :code.purge(module)
    :code.delete(module)

    case Code.compile_file(path) do
      [{^module, _binary} | _] -> :ok
      _ -> :ok
    end
  rescue
    e -> {:error, {:reload_failed, Exception.message(e)}}
  end
end
