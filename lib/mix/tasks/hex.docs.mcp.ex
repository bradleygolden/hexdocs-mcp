defmodule Mix.Tasks.Hex.Docs.Mcp do
  use Mix.Task
  @shortdoc "Downloads Hex docs, converts to markdown chunks, and generates embeddings"

  @requirements ["app.config", "app.start"]

  @moduledoc """
  Fetches Hex docs for a package, converts HTML to markdown, creates semantic chunks, and generates embeddings by default.

  ## Usage

      $ mix hex.docs.mcp COMMAND [options] PACKAGE [VERSION]

  * `COMMAND` - Either `fetch` or `search` (required)
  * `PACKAGE` - Hex package name to work with (required for fetch/search)
  * `VERSION` - Package version to work with (optional, defaults to latest)

  ## Options

      --model MODEL    - Ollama model to use for embeddings (default: nomic-embed-text)
      --query QUERY    - Query string for search command (or --search in legacy mode)

  ## Examples

      $ mix hex.docs.mcp fetch phoenix              # Download, chunk docs and generate embeddings
      $ mix hex.docs.mcp fetch --model all-minilm phoenix   # Use custom model for embeddings
      $ mix hex.docs.mcp search --query "channels" phoenix  # Search in existing embeddings

  ## Legacy Mode (still supported)

      $ mix hex.docs.mcp --query "channels" phoenix  # Equivalent to search command
      $ mix hex.docs.mcp phoenix                     # Equivalent to fetch command

  The fetch command:
  1. Downloads docs using mix hex.docs
  2. Converts HTML to a single markdown file
  3. Chunks the markdown text for embedding in vector databases
  4. Generates embeddings using Ollama
  5. Automatically creates the database if it doesn't exist

  The search command:
  1. Looks up existing embeddings for the specified package
  2. Performs a similarity search using the query
  3. Returns the most relevant results
  """

  def run(["fetch" | args]) do
    Application.ensure_all_started(:hexdocs_mcp)
    %{package: package, version: version, model: model} = parse_args!(args)
    ensure_database_initialized()
    HexdocsMcp.CLI.process_docs(package, version, model)
  end

  def run(["search" | args]) do
    Application.ensure_all_started(:hexdocs_mcp)
    %{package: package, version: version, model: model, search: search} = parse_args!(args)
    ensure_database_initialized()
    HexdocsMcp.CLI.search(search, package, version, model)
  end

  def run([]) do
    Mix.raise("Package name is required. Usage: mix hex.docs.mcp CMD [options] PACKAGE [VERSION]")
  end

  def run(args) do
    Application.ensure_all_started(:hexdocs_mcp)
    %{package: package, version: version, model: model, search: search} = parse_args!(args)
    ensure_database_initialized()

    if search do
      HexdocsMcp.CLI.search(search, package, version, model)
    else
      HexdocsMcp.CLI.process_docs(package, version, model)
    end
  end

  # Check if database is initialized and initialize if not
  defp ensure_database_initialized do
    # Ensure data directory exists
    data_path = HexdocsMcp.Config.data_path()
    File.mkdir_p(data_path)

    try do
      # Try executing a simple query against the embeddings table
      HexdocsMcp.Repo.query!("SELECT 1 FROM embeddings LIMIT 1")
    rescue
      # If the table doesn't exist, initialize the database
      error in Exqlite.Error ->
        if error.message =~ "no such table" do
          Mix.shell().info("Database not initialized. Running initialization...")
          HexdocsMcp.CLI.init_database()
        else
          # Re-raise if it's a different error
          reraise error, __STACKTRACE__
        end

      # Handle connection errors separately
      _ in DBConnection.ConnectionError ->
        Mix.shell().info("Database connection issue. Running initialization...")
        HexdocsMcp.CLI.init_database()
    end
  end

  defp parse_args!([]) do
    Mix.raise(
      "Package name is required. Usage: mix hex.docs.mcp fetch [options] PACKAGE [VERSION]"
    )
  end

  defp parse_args!(args) do
    {opts, args} =
      OptionParser.parse!(args,
        aliases: [
          m: :model,
          q: :query
        ],
        strict: [
          model: :string,
          query: :string
        ]
      )

    [package | args] = args

    %{
      package: package,
      version: List.first(args) || "latest",
      model: opts[:model] || HexdocsMcp.Config.default_embedding_model(),
      search: opts[:query]
    }
  end
end
