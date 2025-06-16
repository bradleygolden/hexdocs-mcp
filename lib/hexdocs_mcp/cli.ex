defmodule HexdocsMcp.CLI do
  @moduledoc """
  Core functionality for Hex documentation processing via command line.
  """
  use Application

  alias Burrito.Util.Args
  alias HexdocsMcp.CLI.Utils
  alias HexdocsMcp.Migrations
  alias HexdocsMcp.Repo

  @usage """
  Usage: [SYSTEM_COMMAND] COMMAND [options]

  Commands:
    fetch_docs         Download and process docs for a package or project dependencies
                       Use --project PATH to fetch all dependencies from a mix.exs file
    semantic_search    Search in package docs using semantic embeddings
    hex_search         Search for packages on Hex.pm
    fulltext_search    Full-text search on HexDocs

  Options:
    --help, -h         Show this help
  """

  @impl Application
  def start(_type, _args) do
    {:ok, _} = HexdocsMcp.Application.start(nil, nil)
    args = Args.get_arguments()
    main(args)
    System.halt(0)
    {:ok, self()}
  end

  @doc """
  Main entry point for both Mix task and standalone CLI.
  Processes arguments and executes appropriate commands.
  """
  def main([]), do: usage()

  def main(args) do
    ensure_database_initialized()
    do_main(args)
  end

  defp do_main(["fetch_docs" | args]) do
    HexdocsMcp.Config.cli_fetch_docs_module().main(args)
  end

  defp do_main(["semantic_search" | args]) do
    HexdocsMcp.Config.cli_search_module().main(args)
  end

  defp do_main(["hex_search" | args]) do
    HexdocsMcp.CLI.HexSearch.main(args)
  end

  defp do_main(["fulltext_search" | args]) do
    HexdocsMcp.CLI.FulltextSearch.main(args)
  end

  defp do_main(_args), do: usage()

  defp usage do
    @usage
    |> String.replace("[SYSTEM_COMMAND]", HexdocsMcp.Config.system_command())
    |> Utils.output_info()
  end

  defp ensure_database_initialized do
    data_path = HexdocsMcp.Config.data_path()
    File.mkdir_p(data_path)

    try do
      HexdocsMcp.Repo.query!("SELECT 1 FROM embeddings LIMIT 1")
      update_database_schema()
    rescue
      error in Exqlite.Error ->
        if error.message =~ "no such table" do
          Utils.output_info("Database not initialized. Running initialization...")
          init_database()
        else
          reraise error, __STACKTRACE__
        end

      _ in DBConnection.ConnectionError ->
        Utils.output_info("Database connection issue. Running initialization...")
        init_database()
    end
  end

  defp init_database do
    Enum.each(Migrations.create_embeddings_table(), fn sql -> Repo.query!(sql) end)
    Utils.output_info("#{Utils.check()} Database initialized successfully!")
  end

  defp update_database_schema do
    Migrations.update_embeddings_table()
  end
end
