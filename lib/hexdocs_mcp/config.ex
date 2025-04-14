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

  def cli_watch_module do
    Application.get_env(:hexdocs_mcp, :watch_module, HexdocsMcp.CLI.Watch)
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

  def watch_enabled? do
    Application.get_env(:hexdocs_mcp, :watch_enabled, false) ||
      System.get_env("HEXDOCS_MCP_WATCH_ENABLED") in ["true", "1"]
  end

  def watch_poll_interval do
    case System.get_env("HEXDOCS_MCP_WATCH_INTERVAL") do
      nil ->
        Application.get_env(:hexdocs_mcp, :watch_poll_interval, 60_000)

      value ->
        case Integer.parse(value) do
          {interval, _} when interval > 0 -> interval
          _ -> 60_000
        end
    end
  end

  def mix_lock_watcher_module do
    Application.get_env(:hexdocs_mcp, :mix_lock_watcher_module, HexdocsMcp.MixLockWatcher)
  end

  def system_command do
    Application.fetch_env!(:hexdocs_mcp, :system_command)
  end
end
