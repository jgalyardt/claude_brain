defmodule Evo.Validator do
  @moduledoc """
  Validates proposed code changes through multiple safety gates:
  1. Size limit check
  2. AST safety (allowlist-based, not denylist)
  3. Module-level side-effect detection
  4. Compilation check (safe — runs AFTER AST checks)
  5. Test suite execution
  """

  @min_changed_lines 20
  @max_changed_lines 80

  @doc "Returns the maximum allowed changed lines, scaled to module size."
  @spec max_changed_lines(non_neg_integer()) :: non_neg_integer()
  def max_changed_lines(module_line_count \\ 0) do
    # Allow up to 60% of the module to change, clamped between min and max
    scaled = round(module_line_count * 0.6)
    scaled |> max(@min_changed_lines) |> min(@max_changed_lines)
  end

  # Modules whose atoms are allowed to appear in remote calls.
  # Everything else is rejected. This is an ALLOWLIST, not a denylist.
  @allowed_modules [
    Kernel, Enum, List, Map, MapSet, Keyword, String, Integer, Float,
    Atom, Tuple, IO, Inspect, Access, Range, Stream, Function,
    Regex, URI, Path, Base, Bitwise, Agent, Task,
    Evo.Evolvable.PromptBuilder, Evo.Evolvable.Fitness, Evo.Evolvable.Strategy,
    Evo.Evolvable.CreativeDisplay
  ]

  # Functions that must NEVER appear, even via allowed modules.
  # Catches apply/2, apply/3 which bypass module-level checks.
  @banned_function_names [
    :apply, :spawn, :spawn_link, :spawn_monitor,
    :send, :exit, :throw,
    :make_ref, :binary_to_term
  ]

  # Erlang modules that are never allowed (catches :os.cmd, :erlang.open_port, etc.)
  @banned_erlang_atoms [
    :os, :erlang, :file, :code, :erl_eval, :erl_scan, :erl_parse,
    :init, :net_kernel, :rpc, :slave, :httpc, :gen_tcp, :gen_udp, :ssl, :inet
  ]

  @type validation_result :: :ok | {:error, term()}

  @doc """
  Runs all validation gates on a proposal.
  Returns :ok if all gates pass, or {:error, reason} on first failure.

  Gate order matters: AST safety runs BEFORE compilation to prevent
  module-level side effects from executing during Code.compile_string.
  """
  @spec validate(Evo.Proposer.t()) :: validation_result()
  def validate(%Evo.Proposer{} = proposal) do
    with :ok <- check_size_limit(proposal),
         :ok <- check_ast_safety(proposal.new_code),
         :ok <- check_no_module_side_effects(proposal.new_code),
         :ok <- check_compilation(proposal.new_code),
         :ok <- run_tests(proposal.module) do
      :telemetry.execute([:evo, :validation, :complete], %{}, %{
        compiled: true,
        tests_passed: true,
        module: proposal.module
      })

      :ok
    else
      {:error, reason} = err ->
        :telemetry.execute([:evo, :validation, :complete], %{}, %{
          compiled: reason != :compilation_failed,
          tests_passed: reason != :tests_failed,
          module: proposal.module,
          failure_reason: reason
        })

        err
    end
  end

  @doc "Checks that the proposed change is within the size limit."
  @spec check_size_limit(Evo.Proposer.t()) :: validation_result()
  def check_size_limit(%{old_code: old, new_code: new}) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    changed = abs(length(new_lines) - length(old_lines)) + count_different_lines(old_lines, new_lines)
    limit = max_changed_lines(length(old_lines))

    if changed <= limit do
      :ok
    else
      {:error, {:too_many_changes, changed, limit}}
    end
  end

  @doc """
  Checks the AST for safety using an ALLOWLIST approach.

  Rejects:
  - Remote calls to modules not in the allowlist
  - Calls to banned function names (apply, spawn, etc.)
  - References to banned Erlang atoms (:os, :erlang, etc.)
  - Use of Code.eval_*, System.cmd, File write/delete operations, Port, etc.
  """
  @spec check_ast_safety(String.t()) :: validation_result()
  def check_ast_safety(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        violations = find_violations(ast)

        if Enum.empty?(violations) do
          :ok
        else
          {:error, {:unsafe_code, violations}}
        end

      {:error, _} ->
        {:error, :ast_parse_failed}
    end
  end

  @doc """
  Ensures there are no expressions at module level that could cause side effects
  during compilation. Only allows: @attributes, def/defp/defmacro, use/import/alias/require.
  """
  @spec check_no_module_side_effects(String.t()) :: validation_result()
  def check_no_module_side_effects(code) do
    case Code.string_to_quoted(code) do
      {:ok, {:defmodule, _, [_alias, [do: {:__block__, _, body}]]}} ->
        unsafe = Enum.reject(body, &safe_module_level_form?/1)

        if Enum.empty?(unsafe) do
          :ok
        else
          {:error, {:module_level_side_effects, length(unsafe)}}
        end

      {:ok, {:defmodule, _, [_alias, [do: single_form]]}} ->
        if safe_module_level_form?(single_form) do
          :ok
        else
          {:error, {:module_level_side_effects, 1}}
        end

      _ ->
        {:error, :not_a_module}
    end
  end

  @doc "Checks that the code compiles without errors."
  @spec check_compilation(String.t()) :: validation_result()
  def check_compilation(code) do
    Code.compile_string(code)
    :ok
  rescue
    e in [CompileError, SyntaxError, TokenMissingError] ->
      {:error, {:compilation_failed, Exception.message(e)}}
  end

  @doc "Runs the test file for the given module."
  @spec run_tests(module()) :: validation_result()
  def run_tests(module) do
    test_path = Evo.Evolvable.Strategy.test_path(module)

    case System.cmd("mix", ["test", "--", test_path, "--no-deps-check"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> {:error, {:tests_failed, output}}
    end
  rescue
    e -> {:error, {:test_execution_failed, Exception.message(e)}}
  end

  ## AST Safety - Allowlist Walker

  defp find_violations(ast) do
    {_, violations} =
      Macro.prewalk(ast, [], fn node, acc ->
        case check_node(node) do
          :ok -> {node, acc}
          {:violation, reason} -> {node, [reason | acc]}
        end
      end)

    violations
  end

  # Remote call: Module.function(args)
  defp check_node({{:., _, [{:__aliases__, _, mod_parts}, func]}, _, _args}) do
    mod = Module.concat(mod_parts)

    cond do
      func in @banned_function_names ->
        {:violation, {:banned_function, func}}

      mod not in @allowed_modules ->
        {:violation, {:disallowed_module, mod}}

      true ->
        :ok
    end
  end

  # Erlang module call: :os.cmd(), :erlang.open_port()
  defp check_node({{:., _, [erlang_mod, _func]}, _, _args}) when is_atom(erlang_mod) do
    if erlang_mod in @banned_erlang_atoms do
      {:violation, {:banned_erlang_module, erlang_mod}}
    else
      :ok
    end
  end

  # Bare function calls — catch apply/2, apply/3, spawn, etc.
  defp check_node({func, _, args}) when is_atom(func) and is_list(args) do
    if func in @banned_function_names do
      {:violation, {:banned_function, func}}
    else
      :ok
    end
  end

  # Atoms that match banned erlang modules appearing anywhere
  defp check_node(atom) when is_atom(atom) do
    if atom in @banned_erlang_atoms do
      {:violation, {:banned_atom, atom}}
    else
      :ok
    end
  end

  defp check_node(_), do: :ok

  ## Module-Level Side Effect Detection

  # These are the ONLY forms allowed at the top level of a module body.
  defp safe_module_level_form?({form, _, _})
       when form in [
              :def, :defp, :defmacro, :defmacrop, :defguard, :defguardp,
              :defstruct, :defexception, :defimpl, :defoverridable, :defdelegate,
              :use, :import, :alias, :require,
              :@, :moduledoc, :doc, :typedoc, :spec, :type, :typep, :opaque,
              :behaviour, :callback, :macrocallback, :impl, :optional_callbacks
            ],
       do: true

  defp safe_module_level_form?(_), do: false

  defp count_different_lines(old_lines, new_lines) do
    max_len = max(length(old_lines), length(new_lines))

    old_padded = old_lines ++ List.duplicate("", max_len - length(old_lines))
    new_padded = new_lines ++ List.duplicate("", max_len - length(new_lines))

    Enum.zip(old_padded, new_padded)
    |> Enum.count(fn {a, b} -> a != b end)
  end
end
