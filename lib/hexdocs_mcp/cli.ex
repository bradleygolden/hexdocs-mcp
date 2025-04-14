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
    fetch              Download and process docs for a package or project dependencies
                       Use --project PATH to fetch all dependencies from a mix.exs file
    search             Search in package docs using embeddings

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

  defp do_main(["fetch" | args]) do
    HexdocsMcp.Config.cli_fetch_module().main(args)
  end

  defp do_main(["search" | args]) do
    HexdocsMcp.Config.cli_search_module().main(args)
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
end
