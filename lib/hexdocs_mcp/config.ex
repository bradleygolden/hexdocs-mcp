defmodule HexdocsMcp.Config do
  def data_path do
    Application.fetch_env!(:hexdocs_mcp, :data_path)
  end

  def default_embedding_model do
    Application.fetch_env!(:hexdocs_mcp, :default_embedding_model)
  end
end
