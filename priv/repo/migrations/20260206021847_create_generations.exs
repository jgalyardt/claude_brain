defmodule Evo.Repo.Migrations.CreateGenerations do
  use Ecto.Migration

  def change do
    create table(:generations) do
      add :generation_number, :integer, null: false
      add :target_module, :string, null: false
      add :status, :string, null: false
      add :fitness_score, :float, default: 0.0
      add :model_used, :string
      add :tokens_in, :integer, default: 0
      add :tokens_out, :integer, default: 0
      add :reasoning, :text
      add :old_code, :text
      add :new_code, :text

      timestamps()
    end

    create index(:generations, [:generation_number], unique: true)
    create index(:generations, [:status])
  end
end
