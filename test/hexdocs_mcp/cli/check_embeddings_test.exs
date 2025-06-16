defmodule HexdocsMcp.CLI.CheckEmbeddingsTest do
  use HexdocsMcp.DataCase, async: false

  alias HexdocsMcp.CLI.CheckEmbeddings
  alias HexdocsMcp.CLI.FetchDocs

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [package: package(), version: "1.0.0", system_command: system_command]
  end

  describe "check_embeddings/2" do
    test "reports when embeddings exist", %{package: package, version: version} do
      capture_io(fn ->
        assert :ok = FetchDocs.main([package, version])
      end)

      output = capture_io(fn ->
        assert :ok = CheckEmbeddings.main([package, version])
      end)

      assert output =~ ~r/Embeddings exist for #{package} #{version}/
      assert output =~ ~r/Total embeddings:/
    end

    test "reports when embeddings don't exist" do
      package = "nonexistent_package"
      version = "1.0.0"

      output = capture_io(fn ->
        assert :error = CheckEmbeddings.main([package, version])
      end)

      assert output =~ ~r/No embeddings found for #{package} #{version}/
      assert output =~ ~r/Run 'fetch_docs #{package} #{version}' to generate embeddings/
    end

    test "defaults to latest version when not specified", %{package: package} do
      capture_io(fn ->
        assert :ok = FetchDocs.main([package])
      end)

      output = capture_io(fn ->
        assert :error = CheckEmbeddings.main([package])
      end)

      assert output =~ ~r/No embeddings found for #{package} latest/
      assert output =~ ~r/Run 'fetch_docs #{package} latest' to generate embeddings/
    end

    test "shows help with --help flag" do
      output = capture_io(fn ->
        result = CheckEmbeddings.main(["--help"])
        assert result == :ok
      end)

      assert output =~ "Usage:"
      assert output =~ "check_embeddings PACKAGE"
      assert output =~ "Arguments:"
      assert output =~ "Examples:"
    end

  end
end