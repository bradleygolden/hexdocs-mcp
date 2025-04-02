defmodule HexMcp.Schema.Embedding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "embeddings" do
    field :package, :string
    field :version, :string
    field :source_file, :string
    field :source_type, :string
    field :start_byte, :integer
    field :end_byte, :integer
    field :text_snippet, :string
    field :text, :string
    field :vector, :binary

    timestamps()
  end

  @required_fields [:package, :version, :source_file, :text, :vector]
  @optional_fields [:source_type, :start_byte, :end_byte, :text_snippet]

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end