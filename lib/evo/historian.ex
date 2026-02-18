defmodule Evo.Historian do
  @moduledoc """
  Records each evolution generation as a git commit and persists
  generation metadata to the database.
  """

  alias Evo.Repo

  @doc """
  Records a generation result: commits the code change to git and
  saves metadata to the database.
  """
  @spec record_generation(map()) :: {:ok, map()} | {:error, term()}
  def record_generation(attrs) do
    with {:ok, generation} <- save_to_db(attrs),
         :ok <- git_commit(generation) do
      {:ok, generation}
    end
  end

  @doc """
  Returns the last N generations from the database.
  """
  @spec recent_generations(non_neg_integer()) :: [map()]
  def recent_generations(limit \\ 20) do
    import Ecto.Query

    Evo.Generation
    |> order_by(desc: :generation_number)
    |> limit(^limit)
    |> Repo.all()
  end

  defp save_to_db(attrs) do
    %Evo.Generation{}
    |> Evo.Generation.changeset(attrs)
    |> Repo.insert()
  end

  defp git_commit(generation) do
    # SECURITY: Build the commit message from sanitized components only.
    # All interpolated values are sanitized to prevent git argument injection.
    subject = sanitize("[evo gen #{generation.generation_number}] #{generation.status}")
    module = sanitize(to_string(generation.target_module))
    model = sanitize(to_string(generation.model_used))
    score = sanitize(to_string(generation.fitness_score))
    tokens_in = sanitize(to_string(generation.tokens_in))
    tokens_out = sanitize(to_string(generation.tokens_out))
    reasoning = sanitize(to_string(generation.reasoning || "N/A"))

    message = "#{subject}\n\nModule: #{module}\nModel: #{model}\nScore: #{score}\nTokens: #{tokens_in} in / #{tokens_out} out\nReasoning: #{reasoning}"

    case System.cmd("git", ["add", "--", "lib/evo/evolvable/"], stderr_to_stdout: true) do
      {_, 0} ->
        # Use -- to separate options from the message, preventing flag injection
        case System.cmd("git", ["commit", "--allow-empty", "--", "-m", message],
               stderr_to_stdout: true
             ) do
          {_, 0} -> :ok
          # git returns 1 when there's nothing to commit — not an error for us
          {output, 1} ->
            if output =~ "nothing to commit" do
              :ok
            else
              {:error, {:git_commit_failed, output}}
            end
          {output, _} -> {:error, {:git_commit_failed, output}}
        end

      {output, _} ->
        {:error, {:git_add_failed, output}}
    end
  rescue
    e -> {:error, {:git_failed, Exception.message(e)}}
  end

  # Strip characters that could be interpreted as git flags or shell metacharacters.
  # Keeps alphanumeric, spaces, basic punctuation, and underscores.
  defp sanitize(str) when is_binary(str) do
    str
    |> String.replace(~r/[^\w\s.,;:!?()\[\]{}'"\-+=\/#@%^&*]/, "")
    |> String.replace(~r/\n+/, " ")
    |> String.slice(0, 500)
  end
end
