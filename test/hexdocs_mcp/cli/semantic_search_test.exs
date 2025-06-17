defmodule HexdocsMcp.CLI.SemanticSearchTest do
  use HexdocsMcp.DataCase, async: false

  import Mox

  alias HexdocsMcp.CLI.FetchDocs
  alias HexdocsMcp.CLI.SemanticSearch

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [package: package(), version: "1.0.0", system_command: system_command]
  end

  test "searching with package and version", %{package: package, version: version} do
    query = "how to configure channels"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, version])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, version, "--query", query])
        assert_valid_search_results(results, package, version)
      end)

    assert output =~ "Searching for \"#{query}\""
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  test "searching with package only (latest version)", %{package: package} do
    query = "how to handle errors"
    version = "latest"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, "--query", query])
        assert_valid_search_results(results, package, version)
      end)

    assert output =~ "Searching for \"#{query}\""
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  test "searching across all packages (no package specified)" do
    query = "how to configure channels"
    package = package()
    version = "latest"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main(["--query", query])
        assert_valid_search_results(results, package, version)
      end)

    assert output =~ "Searching for \"#{query}\" in all packages"
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  test "searching when no embeddings exist", %{
    package: package,
    version: version,
    system_command: system_command
  } do
    query = "how to configure websockets"

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, version, "--query", query])
        assert results == []
      end)

    assert output =~ "No results found"
    assert output =~ "Make sure you've generated embeddings"
    assert output =~ "#{system_command} fetch_docs #{package} #{version}"
  end

  test "searching when no embeddings exist and no package specified" do
    query = "how to configure websockets"

    Repo.delete_all(HexdocsMcp.Embeddings.Embedding)

    output =
      capture_io(fn ->
        results = SemanticSearch.main(["--query", query])
        assert results == []
      end)

    assert output =~ "No results found"
    assert output =~ "Try searching for a specific package or generate embeddings for packages first"
    refute output =~ "Make sure you've generated embeddings"
  end

  test "searching with help flag", %{system_command: system_command} do
    output =
      capture_io(fn ->
        SemanticSearch.main(["--help"])
      end)

    assert output =~ "Usage: #{system_command} semantic_search [PACKAGE]"
    assert output =~ "Arguments:"
    assert output =~ "PACKAGE    - Hex package name to search in (optional"
    assert output =~ "Options:"
    assert output =~ "--query"
    assert output =~ "--version VERSION"
    assert output =~ "--all-versions"
    assert output =~ "Examples:"
    assert output =~ "search --query"
  end

  test "searching with invalid arguments" do
    output =
      capture_io(fn ->
        assert [] = SemanticSearch.main([])
      end)

    assert output =~ "No results found"

    output =
      capture_io(fn ->
        assert [] = SemanticSearch.main(["phoenix"])
      end)

    assert output =~ "No results found"

    package = "invalid/package"
    query = "test query"

    output =
      capture_io(fn ->
        SemanticSearch.main([package, "--query", query])
      end)

    assert output =~ "No results found"
  end

  test "searching with custom limit", %{package: package, version: version} do
    query = "how to configure channels"
    limit = 5

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, version])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, version, "--query", query, "--limit", "#{limit}"])
        assert_valid_search_results(results, package, version)
        assert length(results) <= limit
      end)

    assert output =~ "Searching for \"#{query}\""
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  test "searching with --version flag", %{package: package} do
    query = "how to configure channels"
    version = "1.0.0"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, "1.0.0"])
      assert :ok = FetchDocs.main([package, "2.0.0"])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, "--query", query, "--version", version])
        assert_valid_search_results(results, package, version)

        Enum.each(results, fn result ->
          assert result.metadata.version == version
        end)
      end)

    assert output =~ "Searching for \"#{query}\" in #{package} version #{version}"
    assert output =~ "Package: #{package}"
    assert output =~ "Version: #{version}"
  end

  test "searching with --all-versions flag", %{package: package} do
    query = "how to configure channels"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, "1.0.0"])
      assert :ok = FetchDocs.main([package, "2.0.0"])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, "--query", query, "--all-versions"])
        assert is_list(results)
        assert length(results) > 0

        versions = results |> Enum.map(& &1.metadata.version) |> Enum.uniq()
        assert length(versions) > 1
        assert "1.0.0" in versions
        assert "2.0.0" in versions
      end)

    assert output =~ "Searching for \"#{query}\" in #{package} (all versions)"
    assert output =~ "Package: #{package}"
    assert output =~ "Version:"
  end

  test "searching defaults to latest version only", %{package: package} do
    query = "how to configure channels"

    capture_io(fn ->
      assert :ok = FetchDocs.main([package, "1.0.0"])
      assert :ok = FetchDocs.main([package, "2.0.0"])
    end)

    output =
      capture_io(fn ->
        results = SemanticSearch.main([package, "--query", query])
        assert is_list(results)

        Enum.each(results, fn result ->
          assert result.metadata.version == "2.0.0"
        end)
      end)

    assert output =~ "Searching for \"#{query}\" in #{package} (latest versions only)"
    assert output =~ "Package: #{package}"
    assert output =~ "Version: 2.0.0"
  end

  defp assert_valid_search_results(results, package, version) do
    assert is_list(results)
    assert length(results) > 0

    Enum.each(results, fn result ->
      assert %{score: score, metadata: metadata} = result
      assert is_float(score)
      assert score >= 0 and score <= 1
      assert metadata.package == package

      expected_version = if version == "latest", do: "1.0.0", else: version
      assert metadata.version == expected_version

      assert metadata.source_file
      assert metadata.text_snippet
    end)
  end
end
