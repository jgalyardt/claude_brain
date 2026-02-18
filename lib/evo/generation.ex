defmodule Evo.Generation do
  @moduledoc """
  Ecto schema for tracking evolution generations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "generations" do
    field :generation_number, :integer
    field :target_module, :string
    field :status, :string
    field :fitness_score, :float, default: 0.0
    field :model_used, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :reasoning, :string
    field :old_code, :string
    field :new_code, :string

    timestamps()
  end

  @required_fields [:generation_number, :target_module, :status]
  @optional_fields [:fitness_score, :model_used, :tokens_in, :tokens_out, :reasoning, :old_code, :new_code]

  def changeset(generation, attrs) do
    generation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, [
      "accepted",
      "accepted_neutral",
      "rejected_regression",
      "rejected_validation",
      "error"
    ])
  end
end
