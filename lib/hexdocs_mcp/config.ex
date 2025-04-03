defmodule HexdocsMcp.Config do
  def data_path do
    path = System.get_env("HEXDOCS_MCP_PATH") || Path.join(System.user_home(), ".hexdocs_mcp")
    Application.get_env(:hexdocs_mcp, :data_path, path)
  end

  def database do
    Path.join(data_path(), "hexdocs_mcp.db")
  end

  def default_embedding_model do
    model = System.get_env("HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL") || "nomic-embed-text"
    Application.get_env(:hexdocs_mcp, :default_embedding_model, model)
  end
end
