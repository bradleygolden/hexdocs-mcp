defmodule HexdocsMcp.Config do
  @moduledoc false
  def data_path do
    Application.fetch_env!(:hexdocs_mcp, :data_path)
  end

  def database do
    repo_config = Application.fetch_env!(:hexdocs_mcp, HexdocsMcp.Repo)
    Keyword.fetch!(repo_config, :database)
  end

  def default_embedding_model do
    Application.fetch_env!(:hexdocs_mcp, :default_embedding_model)
  end

  def embeddings_module do
    Application.get_env(:hexdocs_mcp, :embeddings_module, HexdocsMcp.Embeddings)
  end

  def docs_module do
    Application.get_env(:hexdocs_mcp, :docs_module, HexdocsMcp.Docs)
  end

  def cli_fetch_module do
    Application.get_env(:hexdocs_mcp, :fetch_module, HexdocsMcp.CLI.Fetch)
  end

  def cli_search_module do
    Application.get_env(:hexdocs_mcp, :search_module, HexdocsMcp.CLI.Search)
  end

  def ollama_client do
    Application.get_env(:hexdocs_mcp, :ollama_client, Ollama)
  end

  def system_command do
    Application.fetch_env!(:hexdocs_mcp, :system_command)
  end
end
