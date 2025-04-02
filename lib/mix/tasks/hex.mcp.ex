defmodule Mix.Tasks.Hex.Mcp do
  use Mix.Task
  @shortdoc "Downloads Hex docs, converts to markdown chunks, and generates embeddings"

  @requirements ["app.config", "app.start"]

  @moduledoc """
  Fetches Hex docs for a package, converts HTML to markdown, creates semantic chunks, and generates embeddings by default.

  ## Usage

      $ mix hex.mcp [options] PACKAGE [VERSION]

  * `PACKAGE` - Hex package name to download docs for (required)
  * `VERSION` - Package version to download (optional, defaults to latest)

  ## Options

      --no-embed       - Skip generating embeddings after chunking
      --model MODEL    - Ollama model to use for embeddings (default: nomic-embed-text)
      --search QUERY   - Search the generated embeddings with the given query
      --sqlite         - Use SQLite database for storing and searching embeddings (default)
      --lancedb        - Use LanceDB for searching embeddings (backward compatibility)

  ## Examples

      $ mix hex.mcp phoenix                # Download, chunk docs and generate embeddings
      $ mix hex.mcp --no-embed phoenix     # Download and chunk docs without embeddings
      $ mix hex.mcp --search "channels" phoenix  # Search in existing embeddings
      $ mix hex.mcp --model all-minilm phoenix   # Use custom model for embeddings
      $ mix hex.mcp --search "channels" --sqlite phoenix  # Search using SQLite

  The task:
  1. Downloads docs using mix hex.docs
  2. Converts HTML to a single markdown file
  3. Chunks the markdown text for embedding in vector databases
  4. Generates embeddings using Ollama (unless --no-embed is specified)
  5. Stores embeddings in SQLite database
  6. Optionally searches in the generated embeddings using SQLite or files
  """

  def run(args) do
    {opts, args} =
      OptionParser.parse!(args,
        strict: [
          embed: :boolean,
          no_embed: :boolean,
          model: :string,
          search: :string,
          sqlite: :boolean,
          lancedb: :boolean
        ]
      )

    case args do
      [] ->
        Mix.raise("Package name is required. Usage: mix hex.mcp [options] PACKAGE [VERSION]")

      [package | rest] ->
        version = List.first(rest)
        package = String.trim(package)
        model = opts[:model] || "nomic-embed-text"
        
        # Default to embedding unless explicitly disabled with --no-embed
        embed = if opts[:no_embed], do: false, else: true

        # For backward compatibility, if --embed is explicitly set, honor it
        embed = if is_nil(opts[:embed]), do: embed, else: opts[:embed]

        # Prepare options for processing docs
        processing_opts = opts |> Map.new() |> Map.put(:embed, embed)

        # Handle search-only case
        if opts[:search] do
          search_query = opts[:search]
          
          # Determine which storage system to use
          use_sqlite = !opts[:lancedb]
          
          storage_type = cond do
            opts[:lancedb] -> "LanceDB (file-based)"
            opts[:sqlite] -> "SQLite"
            true -> "SQLite"
          end

          header_line = String.duplicate("=", 60)
          Mix.shell().info(header_line)
          Mix.shell().info("SEARCH QUERY: \"#{search_query}\"")
          Mix.shell().info("PACKAGE: #{package} #{version || "latest"}")
          Mix.shell().info("MODEL: #{model}")
          Mix.shell().info("STORAGE: #{storage_type}")
          Mix.shell().info(header_line)

          results = HexMcp.Embeddings.search(search_query, package, version, model, 3, use_sqlite)

          if Enum.empty?(results) do
            Mix.shell().info(
              "No results found. Make sure you've generated embeddings for this package first."
            )
          else
            Mix.shell().info("\n✨ TOP RESULTS:")

            Enum.each(results, fn %{score: score, metadata: metadata} ->
              Mix.shell().info("\n#{IO.ANSI.bright()}Score: #{:io_lib.format("~.3f", [score])}#{IO.ANSI.reset()}")
              Mix.shell().info("#{IO.ANSI.yellow()}File: #{metadata.source_file}#{IO.ANSI.reset()}")
              Mix.shell().info("#{IO.ANSI.bright()}Text:#{IO.ANSI.reset()} #{metadata.text_snippet}")
            end)
            
            Mix.shell().info("\n#{IO.ANSI.green()}Search completed successfully!#{IO.ANSI.reset()}")
          end

          # Don't process docs when doing a search, regardless of embed setting
          # Search is a read-only operation
        else
          # No search, just regular processing
          process_docs(package, version, model, processing_opts)
        end
    end
  end

  defp process_docs(package, version, model, opts) do
    # Continue with normal processing
    ensure_markdown_dir!()
    ensure_markdown_dir!(package)
    docs_path = fetch_docs(package, version)

    # Verify docs_path exists
    if !File.dir?(docs_path) do
      Mix.raise("Docs directory not found: #{docs_path}")
    end

    Mix.shell().info("Using docs from: #{docs_path}")

    output_file = create_markdown_file(package, version)
    html_files = find_html_files(docs_path)

    if Enum.empty?(html_files) do
      Mix.raise("No HTML files found in docs directory: #{docs_path}")
    end

    Mix.shell().info("Converting #{length(html_files)} HTML files to markdown...")
    convert_html_files_to_markdown(html_files, output_file)

    # Create chunks directory
    chunks_dir = Path.join([".hex_mcp", package, "chunks"])
    File.mkdir_p!(chunks_dir)

    # Chunk the markdown text
    Mix.shell().info("Creating semantic text chunks for vector embedding...")
    chunk_count = create_text_chunks(output_file, chunks_dir, package, version)

    Mix.shell().info("Markdown docs created at: #{output_file}")
    Mix.shell().info("#{chunk_count} chunks created in: #{chunks_dir}")

    # Generate embeddings if requested
    if opts[:embed] do
      Mix.shell().info("Generating embeddings using Ollama model: #{model}...")
      {:ok, count} = HexMcp.Embeddings.generate_embeddings(package, version, model)
      Mix.shell().info("Successfully generated #{count} embeddings")
    end
  end

  defp ensure_markdown_dir!(package \\ nil) do
    if package do
      # Create package-specific directory
      File.mkdir_p!(Path.join(".hex_mcp", package))
    else
      # Create base directory
      File.mkdir_p!(".hex_mcp")
    end
  end

  defp fetch_docs(package, version) do
    # Call hex docs with the package and version using System.cmd
    args =
      if version do
        ["hex.docs", "fetch", package, version]
      else
        ["hex.docs", "fetch", package]
      end

    {output, exit_code} = System.cmd("mix", args, stderr_to_stdout: true)

    if exit_code != 0 do
      Mix.raise("Failed to fetch docs: \n#{output}")
    end

    # Parse output to find where docs were saved
    # The output contains either:
    # - "Docs fetched to /path/to/docs"
    # - "Docs already fetched: /path/to/docs"
    docs_path =
      output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        cond do
          # Match "Docs fetched to"
          Regex.match?(~r/Docs fetched to (.+)/, line) ->
            [_, path] = Regex.run(~r/Docs fetched to (.+)/, line)
            path

          # Match "Docs already fetched:"
          Regex.match?(~r/Docs already fetched: (.+)/, line) ->
            [_, path] = Regex.run(~r/Docs already fetched: (.+)/, line)
            path

          true ->
            nil
        end
      end)

    if is_nil(docs_path) do
      # If we couldn't parse the path from the output, log and use the default location
      Mix.shell().info("Could not parse docs path from output: \n#{output}")
      docs_base = Mix.Project.deps_path() |> Path.join("docs")

      if version do
        Path.join([docs_base, "hexpm", package, version])
      else
        # Find latest version directory
        Path.join([docs_base, "hexpm", package])
        |> File.ls!()
        |> Enum.filter(fn dir ->
          path = Path.join([docs_base, "hexpm", package, dir])
          File.dir?(path) && String.match?(dir, ~r/\d+\.\d+\.\d+.*/)
        end)
        |> Enum.sort_by(fn dir ->
          case Version.parse(dir) do
            {:ok, version} -> version
            :error -> Version.parse!("0.0.0")
          end
        end)
        |> List.last()
        |> then(fn latest_version ->
          Path.join([docs_base, "hexpm", package, latest_version])
        end)
      end
    else
      docs_path
    end
  end

  defp create_markdown_file(package, version) do
    version_str = if version, do: version, else: "latest"
    Path.join([".hex_mcp", package, "#{version_str}.md"])
  end

  defp find_html_files(docs_path) do
    Path.wildcard(Path.join(docs_path, "**/*.html"))
  end

  defp convert_html_files_to_markdown(html_files, output_file) do
    File.open!(output_file, [:write, :utf8], fn file ->
      Enum.each(html_files, fn html_file ->
        html_content = File.read!(html_file)
        relative_path = Path.relative_to(html_file, Mix.Project.deps_path())

        # Write file metadata as h1
        IO.write(file, "---\n\n")
        IO.write(file, "# #{relative_path}\n\n")

        # Convert HTML to markdown
        markdown = Html2Markdown.convert(html_content)
        IO.write(file, markdown)
        IO.write(file, "\n\n---\n\n")
      end)
    end)
  end

  defp create_text_chunks(markdown_file, output_dir, package, version) do
    # Read markdown content
    markdown_content = File.read!(markdown_file)

    # Split content by file markers (---) to get chunks by file
    file_chunks = String.split(markdown_content, ~r/^---$/m, trim: true)

    chunk_count =
      file_chunks
      |> Enum.with_index()
      |> Enum.flat_map(fn {file_chunk, idx} ->
        # Extract file path from the content (assumes format "# path")
        file_path =
          case Regex.run(~r/# ([^\n]+)/, file_chunk) do
            [_, path] -> path
            _ -> "Unknown-#{idx}"
          end

        # Skip empty chunks, unknown chunks, and helper pages
        if String.trim(file_chunk) == "" or
             String.starts_with?(file_path, "Unknown") or
             Path.basename(file_path) in ["404.html", "search.html"] do
          []
        else
          # Clean up file path for use in filenames
          clean_path =
            file_path
            |> Path.basename()
            |> Path.rootname()
            |> String.replace(~r/[^\w\d\.-]/, "_")

          # Create chunk metadata
          metadata = %{
            package: package,
            version: version || "latest",
            source_file: file_path,
            source_type: "hexdocs"
          }

          # Use TextChunker to create semantic chunks
          # We'll use a reasonable token size for vector embedding (around 2000 chars)
          chunks =
            TextChunker.split(
              file_chunk,
              chunk_size: 2000,
              chunk_overlap: 200,
              format: :markdown
            )

          # Write each chunk to a separate file
          chunks
          |> Enum.with_index()
          |> Enum.map(fn {chunk, chunk_idx} ->
            # Skip chunks that are too small (likely just headers or whitespace)
            if String.length(chunk.text) < 50 do
              nil
            else
              # Create a unique file name
              chunk_filename = "#{clean_path}_chunk_#{chunk_idx}.json"
              chunk_path = Path.join(output_dir, chunk_filename)

              # Format chunk for storage - combine TextChunker's chunk with our metadata
              chunk_data = %{
                "text" => chunk.text,
                "metadata" =>
                  Map.merge(metadata, %{
                    start_byte: chunk.start_byte,
                    end_byte: chunk.end_byte
                  })
              }

              # Write chunk as JSON
              chunk_json = Jason.encode!(chunk_data, pretty: true)
              File.write!(chunk_path, chunk_json)

              chunk
            end
          end)
          |> Enum.reject(&is_nil/1)
        end
      end)
      |> Enum.count()

    chunk_count
  end
end
