defmodule HexdocsMcp.CLI.SearchTest do
  use HexdocsMcp.DataCase, async: false

  import Mox

  alias HexdocsMcp.CLI.Fetch
  alias HexdocsMcp.CLI.Search

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [package: package(), version: "1.0.0", system_command: system_command]
  end

  test "searching with package and version", %{package: package, version: version} do
    query = "how to configure channels"

    capture_io(fn ->
      assert :ok = Fetch.main([package, version])
    end)

    output =
      capture_io(fn ->
        results = Search.main([package, version, "--query", query])
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
      assert :ok = Fetch.main([package])
    end)

    output =
      capture_io(fn ->
        results = Search.main([package, "--query", query])
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
      assert :ok = Fetch.main([package])
    end)

    output =
      capture_io(fn ->
        results = Search.main(["--query", query])
        # Results should come from all packages, but in this test we only have one package
        assert_valid_search_results(results, package, version)
      end)

    assert output =~ "Searching for \"#{query}\" in all packages"
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  test "searching with custom model", %{package: package, version: version} do
    query = "how to handle authentication"
    custom_model = "all-minilm"

    capture_io(fn ->
      assert :ok = Fetch.main([package, version, "--model", custom_model])
    end)

    output =
      capture_io(fn ->
        results = Search.main([package, version, "--query", query, "--model", custom_model])
        assert_valid_search_results(results, package, version)
      end)

    assert output =~ "Searching for \"#{query}\""
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
        results = Search.main([package, version, "--query", query])
        assert results == []
      end)

    # Verify the output contains instructions for generating embeddings
    assert output =~ "No results found"
    assert output =~ "Make sure you've generated embeddings"
    assert output =~ "#{system_command} fetch #{package} #{version}"
  end

  test "searching when no embeddings exist and no package specified" do
    query = "how to configure websockets"

    # Ensure no embeddings exist
    Repo.delete_all(HexdocsMcp.Embeddings.Embedding)

    output =
      capture_io(fn ->
        results = Search.main(["--query", query])
        assert results == []
      end)

    # Verify the output contains appropriate message for all-package search
    assert output =~ "No results found"
    assert output =~ "Try searching for a specific package or generate embeddings for packages first"
    # This should only appear when a package is specified
    refute output =~ "Make sure you've generated embeddings"
  end

  test "searching with help flag", %{system_command: system_command} do
    output =
      capture_io(fn ->
        Search.main(["--help"])
      end)

    assert output =~ "Usage: #{system_command} search [PACKAGE] [VERSION]"
    assert output =~ "Arguments:"
    assert output =~ "PACKAGE    - Hex package name to search in (optional"
    assert output =~ "VERSION"
    assert output =~ "Options:"
    assert output =~ "--query"
    assert output =~ "--model"
    assert output =~ "Examples:"
    # Test the new example for searching all packages
    assert output =~ "search --query"
  end

  test "searching with invalid arguments" do
    output =
      capture_io(fn ->
        assert [] = Search.main([])
      end)

    assert output =~ "No results found"

    output =
      capture_io(fn ->
        assert [] = Search.main(["phoenix"])
      end)

    assert output =~ "No results found"

    package = "invalid/package"
    query = "test query"

    output =
      capture_io(fn ->
        Search.main([package, "--query", query])
      end)

    assert output =~ "No results found"
  end

  test "searching with custom limit", %{package: package, version: version} do
    query = "how to configure channels"
    limit = 5

    capture_io(fn ->
      assert :ok = Fetch.main([package, version])
    end)

    output =
      capture_io(fn ->
        results = Search.main([package, version, "--query", query, "--limit", "#{limit}"])
        assert_valid_search_results(results, package, version)
        assert length(results) <= limit
      end)

    assert output =~ "Searching for \"#{query}\""
    assert output =~ "Found"
    assert output =~ "Result (score:"
    assert output =~ "File:"
    assert output =~ "Text:"
  end

  # Helper functions
  defp assert_valid_search_results(results, package, version) do
    assert is_list(results)
    assert length(results) > 0

    Enum.each(results, fn result ->
      assert %{score: score, metadata: metadata} = result
      assert is_float(score)
      assert score >= 0 and score <= 1
      assert metadata.package == package
      assert metadata.version == version
      assert metadata.source_file
      assert metadata.text_snippet
    end)
  end
end
