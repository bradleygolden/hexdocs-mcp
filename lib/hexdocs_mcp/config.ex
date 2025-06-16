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

  def cli_fetch_docs_module do
    Application.get_env(:hexdocs_mcp, :fetch_docs_module, HexdocsMcp.CLI.FetchDocs)
  end

  def cli_search_module do
    Application.get_env(:hexdocs_mcp, :search_module, HexdocsMcp.CLI.SemanticSearch)
  end

  def ollama_client do
    Application.get_env(:hexdocs_mcp, :ollama_client, Ollama)
  end

  def mix_deps_module do
    Application.get_env(:hexdocs_mcp, :mix_deps_module, HexdocsMcp.MixDeps)
  end

  def project_paths do
    project_paths = Application.fetch_env!(:hexdocs_mcp, :project_paths)
    parse_project_paths(project_paths)
  end

  defp parse_project_paths(nil), do: []
  defp parse_project_paths(""), do: []

  defp parse_project_paths(paths) do
    paths
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&File.exists?/1)
  end

  def system_command do
    Application.fetch_env!(:hexdocs_mcp, :system_command)
  end

  def hex_search_module do
    Application.get_env(:hexdocs_mcp, :hex_search_module, HexdocsMcp.HexSearch)
  end

  def fulltext_search_module do
    Application.get_env(:hexdocs_mcp, :fulltext_search_module, HexdocsMcp.FulltextSearch)
  end
end
