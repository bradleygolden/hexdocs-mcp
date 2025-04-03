defmodule HexdocsMcp.CLI do
  @moduledoc """
  Core functionality for Hex documentation processing via command line.
  """

  alias HexdocsMcp.CLI.Progress
  alias HexdocsMcp.{Repo, Migrations, Markdown}

  @doc """
  Initialize the database and required tables.
  """
  def init_database do
    Migrations.create_embeddings_table()
    |> Enum.each(fn sql -> Repo.query!(sql) end)

    Mix.shell().info("#{check()} Database initialized successfully!")
  end

  @doc """
  Process documentation for a package and optionally generate embeddings.
  """
  def process_docs(package, version, model) do
    alias HexdocsMcp.CLI.Progress

    # Simple, minimal status updates
    ensure_markdown_dir!(package)

    # Fetch docs - quiet output
    Mix.shell().info(
      "Fetching documentation for #{package}#{if version, do: " #{version}", else: ""}..."
    )

    docs_path = execute_docs_fetch_quietly(package, version)
    verify_docs_path!(docs_path)

    # Prepare file paths and convert HTML
    output_file = create_markdown_file(package, version)
    html_files = find_html_files(docs_path)
    verify_html_files!(html_files, docs_path)

    # Simple status without spinner
    Mix.shell().info("Converting #{length(html_files)} HTML files to markdown...")
    convert_html_files_to_markdown(html_files, output_file)

    # Prepare chunking
    chunks_dir = prepare_chunks_dir(package)

    # Create chunks - simple status
    Mix.shell().info("Creating semantic text chunks...")
    chunk_count = create_text_chunks(output_file, chunks_dir, package, version)

    # Generate embeddings - show progress bar only for this step
    Mix.shell().info("Generating embeddings using #{model}...")

    {:ok, embed_count} =
      HexdocsMcp.generate_embeddings(
        package,
        version,
        model,
        progress_callback: create_embedding_progress_callback()
      )

    # Summary info
    Mix.shell().info("#{check()} Processing completed:")
    Mix.shell().info("  • Docs location: #{docs_path}")
    Mix.shell().info("  • Markdown file: #{output_file}")
    Mix.shell().info("  • Created #{chunk_count} chunks in: #{chunks_dir}")
    Mix.shell().info("  • Generated #{embed_count} embeddings")

    %{
      package: package,
      version: version || "latest",
      chunks_count: chunk_count,
      embeddings_created: true
    }
  end

  # Execute hex.docs.fetch without verbose output
  defp execute_docs_fetch_quietly(package, version) do
    {output, 0} = execute_hex_docs_fetch(package, version)
    parse_docs_path(output, package, version)
  end

  @doc """
  Search for specific content in a package's documentation.
  """
  def search(query, package, version, model) do
    alias HexdocsMcp.CLI.Progress

    # Print minimal header for context
    Mix.shell().info("Searching for \"#{query}\" in #{package} #{version || "latest"}...")

    # Simple progress for search with progress bar only
    progress_callback = create_search_progress_callback()
    results = perform_search(query, package, version, model, progress_callback)

    # Display results
    display_search_results(results, package, version)
    results
  end

  defp verify_docs_path!(docs_path) do
    unless File.dir?(docs_path), do: raise("Docs directory not found: #{docs_path}")
  end

  defp verify_html_files!(html_files, docs_path) do
    if Enum.empty?(html_files), do: raise("No HTML files found in docs directory: #{docs_path}")
  end

  defp prepare_chunks_dir(package) do
    data_path = HexdocsMcp.Config.data_path()
    chunks_dir = Path.join([data_path, package, "chunks"])
    File.mkdir_p!(chunks_dir)
    chunks_dir
  end

  defp create_markdown_file(package, version) do
    data_path = HexdocsMcp.Config.data_path()
    version_str = if version, do: version, else: "latest"
    Path.join([data_path, package, "#{version_str}.md"])
  end

  defp create_embedding_progress_callback do
    # We'll use process dictionary to track progress state
    # This is acceptable for ephemeral UI state

    fn current, total, step ->
      step = step || :processing

      case step do
        :processing ->
          progress_fn =
            case Process.get(:processing_progress_fn) do
              nil ->
                # Initialize on first call with correct total
                fn_with_total = Progress.progress_bar("Processing embeddings", total)
                Process.put(:processing_progress_fn, fn_with_total)
                fn_with_total

              existing ->
                existing
            end

          # Progress bar's own completion message will be shown when current == total
          progress_fn.(current)

        :saving ->
          progress_fn =
            case Process.get(:saving_progress_fn) do
              nil ->
                # Initialize on first call with correct total
                fn_with_total = Progress.progress_bar("Saving embeddings", total)
                Process.put(:saving_progress_fn, fn_with_total)
                fn_with_total

              existing ->
                existing
            end

          # Progress bar's own completion message will be shown when current == total
          progress_fn.(current)

        _ ->
          # Default to processing
          progress_fn =
            Process.get(
              :processing_progress_fn,
              Progress.progress_bar("Processing embeddings", total)
            )

          # Progress bar's own completion message will be shown when current == total
          progress_fn.(current)
      end
    end
  end

  defp create_search_progress_callback do
    fn current, total, step ->
      step = step || :computing

      if step == :computing do
        # Get or create the progress function
        progress_fn =
          case Process.get(:search_progress_fn) do
            nil ->
              fn_with_correct_total = Progress.progress_bar("Computing similarity scores", total)
              Process.put(:search_progress_fn, fn_with_correct_total)
              fn_with_correct_total

            existing_fn ->
              existing_fn
          end

        # Progress bar's own completion message will be shown when current == total
        progress_fn.(current)
      end
    end
  end

  defp perform_search(query, package, version, model, progress_callback) do
    HexdocsMcp.search_embeddings(
      query,
      package,
      version,
      model,
      top_k: 3,
      progress_callback: progress_callback
    )
  end

  defp display_search_results([], package, version) do
    cmd = String.trim("mix hex.docs.mcp fetch #{package} #{version}")

    Mix.shell().info("No results found.")
    Mix.shell().info("Make sure you've generated embeddings for this package first by running:")
    Mix.shell().info("  #{cmd}")
  end

  defp display_search_results(results, _package, _version) do
    Mix.shell().info("#{check()} Found #{length(results)} results:")

    Enum.each(results, fn %{score: score, metadata: metadata} ->
      # Format score to 3 decimal places
      formatted_score = :io_lib.format("~.3f", [score]) |> IO.iodata_to_binary()

      Mix.shell().info(
        "\n#{IO.ANSI.bright()}Result (score: #{formatted_score})#{IO.ANSI.reset()}"
      )

      Mix.shell().info("  File: #{metadata.source_file}")
      Mix.shell().info("  Text: #{metadata.text_snippet}")
    end)
  end

  defp ensure_markdown_dir!(package) do
    data_path = HexdocsMcp.Config.data_path()
    File.mkdir_p!(Path.join(data_path, package))
  end

  defp execute_hex_docs_fetch(package, version) do
    args =
      if version != "latest",
        do: ["hex.docs", "fetch", package, version],
        else: ["hex.docs", "fetch", package]

    result = System.cmd("mix", args, stderr_to_stdout: true)

    case result do
      {output, 0} -> {output, 0}
      {output, _} -> raise "Failed to fetch docs: \n#{output}"
    end
  end

  defp parse_docs_path(output, package, version) do
    docs_path = extract_docs_path_from_output(output)
    docs_path || find_default_docs_path(package, version, output)
  end

  defp extract_docs_path_from_output(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(&extract_path_from_line/1)
  end

  defp extract_path_from_line(line) do
    cond do
      Regex.match?(~r/Docs fetched to (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs fetched to (.+)/, line)
        path

      Regex.match?(~r/Docs already fetched: (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs already fetched: (.+)/, line)
        path

      Regex.match?(~r/Docs fetched: (.+)/, line) ->
        [_, path] = Regex.run(~r/Docs fetched: (.+)/, line)
        path

      true ->
        nil
    end
  end

  defp find_default_docs_path(package, version, output) do
    Mix.shell().info("Could not parse docs path from output: \n#{output}")
    docs_base = Mix.Project.deps_path() |> Path.join("docs")

    if version do
      Path.join([docs_base, "hexpm", package, version])
    else
      find_latest_version_path(docs_base, package)
    end
  end

  defp find_latest_version_path(docs_base, package) do
    package_path = Path.join([docs_base, "hexpm", package])

    package_path
    |> File.ls!()
    |> Enum.filter(&version_directory?(&1, docs_base, package))
    |> Enum.sort_by(&parse_version/1)
    |> List.last()
    |> build_version_path(docs_base, package)
  end

  defp version_directory?(dir, docs_base, package) do
    path = Path.join([docs_base, "hexpm", package, dir])
    File.dir?(path) && String.match?(dir, ~r/\d+\.\d+\.\d+.*/)
  end

  defp parse_version(dir) do
    case Version.parse(dir) do
      {:ok, version} -> version
      :error -> Version.parse!("0.0.0")
    end
  end

  defp build_version_path(latest_version, docs_base, package) do
    Path.join([docs_base, "hexpm", package, latest_version])
  end

  defp find_html_files(docs_path) do
    Path.wildcard(Path.join(docs_path, "**/*.html"))
  end

  defp convert_html_files_to_markdown(html_files, output_file) do
    File.open!(output_file, [:write, :utf8], &write_markdown_content(&1, html_files))
  end

  defp write_markdown_content(file, html_files) do
    Enum.each(html_files, fn html_file ->
      html_content = File.read!(html_file)
      relative_path = Path.relative_to(html_file, Mix.Project.deps_path())

      IO.write(file, "---\n\n")
      IO.write(file, "# #{relative_path}\n\n")
      IO.write(file, Markdown.from_html(html_content))
      IO.write(file, "\n\n---\n\n")
    end)
  end

  defp create_text_chunks(markdown_file, output_dir, package, version) do
    markdown_file
    |> File.read!()
    |> String.split(~r/^---$/m, trim: true)
    |> process_file_chunks(output_dir, package, version)
    |> Enum.count()
  end

  defp process_file_chunks(file_chunks, output_dir, package, version) do
    file_chunks
    |> Enum.with_index()
    |> Enum.flat_map(&process_file_chunk(&1, output_dir, package, version))
  end

  defp process_file_chunk({file_chunk, idx}, output_dir, package, version) do
    file_path = extract_file_path(file_chunk, idx)

    if skip_chunk?(file_chunk, file_path) do
      []
    else
      clean_path = sanitize_path(file_path)
      metadata = build_chunk_metadata(package, version, file_path)

      file_chunk
      |> chunk_text()
      |> create_chunk_files(clean_path, output_dir, metadata)
    end
  end

  defp extract_file_path(file_chunk, idx) do
    case Regex.run(~r/# ([^\n]+)/, file_chunk) do
      [_, path] -> path
      _ -> "Unknown-#{idx}"
    end
  end

  defp skip_chunk?(file_chunk, file_path) do
    String.trim(file_chunk) == "" or
      String.starts_with?(file_path, "Unknown") or
      Path.basename(file_path) in ["404.html", "search.html"]
  end

  defp sanitize_path(file_path) do
    file_path
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[^\w\d\.-]/, "_")
  end

  defp chunk_text(text) do
    TextChunker.split(text, chunk_size: 2000, chunk_overlap: 200, format: :markdown)
  end

  defp build_chunk_metadata(package, version, file_path) do
    %{
      package: package,
      version: version || "latest",
      source_file: file_path,
      source_type: "hexdocs"
    }
  end

  defp create_chunk_files(chunks, clean_path, output_dir, metadata) do
    chunks
    |> Enum.with_index()
    |> Enum.map(&create_chunk_file(&1, clean_path, output_dir, metadata))
    |> Enum.reject(&is_nil/1)
  end

  defp create_chunk_file({chunk, chunk_idx}, clean_path, output_dir, metadata) do
    if String.length(chunk.text) < 50 do
      nil
    else
      chunk_filename = "#{clean_path}_chunk_#{chunk_idx}.json"
      chunk_path = Path.join(output_dir, chunk_filename)

      extended_metadata =
        Map.merge(metadata, %{
          start_byte: chunk.start_byte,
          end_byte: chunk.end_byte
        })

      chunk_data = %{
        "text" => chunk.text,
        "metadata" => extended_metadata
      }

      chunk_json = Jason.encode!(chunk_data, pretty: true)
      File.write!(chunk_path, chunk_json)

      chunk
    end
  end

  defp check() do
    "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
  end
end
