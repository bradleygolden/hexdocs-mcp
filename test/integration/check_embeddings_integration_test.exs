defmodule HexdocsMcp.Integration.CheckEmbeddingsTest do
  @moduledoc """
  Integration tests for the check_embeddings command.

  These tests hit real services and are excluded from the default test run.
  Run with: mix test --include integration test/integration
  """
  use HexdocsMcp.DataCase, async: false

  alias HexdocsMcp.CLI.CheckEmbeddings
  alias HexdocsMcp.CLI.FetchDocs

  @moduletag :integration

  describe "check_embeddings integration" do
    test "checks embeddings for a real package after fetching" do
      package = "jason"
      version = "1.4.1"

      output =
        capture_io(fn ->
          assert :ok = FetchDocs.main([package, version])
        end)

      assert output =~ "Processing completed"
      assert output =~ ~r/Generated \d+ embeddings/

      output =
        capture_io(fn ->
          assert :ok = CheckEmbeddings.main([package, version])
        end)

      assert output =~ ~r/Embeddings exist for #{package} #{version}/
      assert output =~ ~r/Total embeddings: \d+/
    end

    test "reports when no embeddings exist for a package" do
      package = "non_existent_package_xyz_123"

      output =
        capture_io(fn ->
          assert :error = CheckEmbeddings.main([package])
        end)

      assert output =~ ~r/No embeddings found for #{package} latest/
      assert output =~ "Run 'fetch_docs #{package} latest' to generate embeddings"
    end

    test "checks embeddings without version (defaults to latest)" do
      package = "telemetry"

      capture_io(fn ->
        FetchDocs.main([package])
      end)

      output =
        capture_io(fn ->
          result = CheckEmbeddings.main([package])
          assert result in [:ok, :error]
        end)

      assert output =~ ~r/(Embeddings exist for #{package}|No embeddings found for #{package})/
    end

    test "handles packages with multiple versions" do
      package = "decimal"
      version1 = "2.0.0"
      version2 = "2.1.0"

      capture_io(fn ->
        assert :ok = FetchDocs.main([package, version1])
      end)

      output =
        capture_io(fn ->
          assert :ok = CheckEmbeddings.main([package, version1])
        end)

      assert output =~ ~r/Embeddings exist for #{package} #{version1}/

      output =
        capture_io(fn ->
          assert :error = CheckEmbeddings.main([package, version2])
        end)

      assert output =~ ~r/No embeddings found for #{package} #{version2}/
    end
  end
end
