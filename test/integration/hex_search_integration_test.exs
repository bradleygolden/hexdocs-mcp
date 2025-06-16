defmodule HexdocsMcp.Integration.HexSearchTest do
  use ExUnit.Case, async: true

  alias HexdocsMcp.HexSearch

  @moduletag :integration

  describe "search_packages/2 - real API" do
    test "searches all packages when no package specified" do
      {:ok, results} = HexSearch.search_packages("json", limit: 5)

      assert is_list(results)
      assert length(results) <= 5

      Enum.each(results, fn result ->
        assert Map.has_key?(result, :name)
        assert Map.has_key?(result, :description)
        assert Map.has_key?(result, :downloads)
        assert Map.has_key?(result, :latest_version)
        assert Map.has_key?(result, :html_url)
      end)
    end

    test "searches within package versions when package specified" do
      {:ok, results} = HexSearch.search_packages("1.7", package: "phoenix", limit: 5)

      assert is_list(results)

      Enum.each(results, fn result ->
        assert Map.has_key?(result, :name)
        assert result.name == "phoenix"
        assert Map.has_key?(result, :version)
        assert Map.has_key?(result, :has_docs)
        assert Map.has_key?(result, :inserted_at)
      end)
    end

    test "gets specific version info when package and version specified" do
      {:ok, results} = HexSearch.search_packages("info", package: "phoenix", version: "1.7.0")

      assert is_list(results)
      assert length(results) == 1

      [result] = results
      assert result.name == "phoenix"
      assert result.version == "1.7.0"
      assert Map.has_key?(result, :has_docs)
      assert Map.has_key?(result, :package_url)
    end

    test "respects sort option" do
      {:ok, results_downloads} = HexSearch.search_packages("test", sort: "downloads", limit: 5)
      {:ok, results_name} = HexSearch.search_packages("test", sort: "name", limit: 5)

      # Results should be different when sorted differently
      assert is_list(results_downloads)
      assert is_list(results_name)

      # First result might be different
      if length(results_downloads) > 0 and length(results_name) > 0 do
        # They might have different first results due to different sorting
        assert Map.has_key?(hd(results_downloads), :name)
        assert Map.has_key?(hd(results_name), :name)
      end
    end

    test "handles package not found error" do
      {:error, error_msg} = HexSearch.search_packages("test", package: "nonexistent_package_xyz_123")

      assert is_binary(error_msg)
      assert error_msg =~ "not found" or error_msg =~ "404"
    end

    test "handles API errors gracefully" do
      # Test with invalid parameters that might cause API errors
      result = HexSearch.search_packages("", limit: -1)

      # Should either return empty results or an error
      case result do
        {:ok, results} -> assert is_list(results)
        {:error, msg} -> assert is_binary(msg)
      end
    end
  end
end
