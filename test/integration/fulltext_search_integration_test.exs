defmodule HexdocsMcp.Integration.FulltextSearchTest do
  use ExUnit.Case, async: true

  alias HexdocsMcp.FulltextSearch

  @moduletag :integration

  describe "search/2 - real API" do
    test "searches across all packages" do
      {:ok, results, search_info} = FulltextSearch.search("GenServer", limit: 5)

      assert is_list(results)
      assert length(results) <= 5

      assert is_map(search_info)
      assert Map.has_key?(search_info, :total_found)
      assert Map.has_key?(search_info, :page)
      assert Map.has_key?(search_info, :per_page)
      assert Map.has_key?(search_info, :search_time_ms)

      Enum.each(results, fn result ->
        assert_valid_search_result(result)
      end)
    end

    test "searches within a specific package" do
      {:ok, results, _search_info} = FulltextSearch.search("LiveView", package: "phoenix_live_view", limit: 3)

      assert is_list(results)

      Enum.each(results, fn result ->
        assert_valid_search_result(result)
        assert result.package =~ "phoenix_live_view"
      end)
    end

    test "searches within a specific package version" do
      {:ok, results, _search_info} =
        FulltextSearch.search("router",
          package: "phoenix",
          version: "1.7.0",
          limit: 3
        )

      assert is_list(results)

      Enum.each(results, fn result ->
        assert_valid_search_result(result)
        assert result.package == "phoenix-1.7.0"
      end)
    end

    test "handles unusual queries" do
      {:ok, results, search_info} = FulltextSearch.search("xyz_nonexistent_query_abc_123_456_789_unusual")

      assert is_list(results)
      assert is_integer(search_info.total_found)
      assert search_info.total_found >= 0
    end

    test "respects limit parameter" do
      {:ok, results, search_info} = FulltextSearch.search("function", limit: 2)

      assert length(results) <= 2
      assert search_info.per_page == 2
    end

    test "includes highlights in results" do
      {:ok, results, _} = FulltextSearch.search("Enum.map", limit: 1)

      assert length(results) > 0
      [result | _] = results

      assert Map.has_key?(result, :snippet)
      assert Map.has_key?(result, :highlights)
      assert is_list(result.highlights)
    end

    test "builds correct URLs" do
      {:ok, results, _} = FulltextSearch.search("GenServer", limit: 1)

      assert length(results) > 0
      [result | _] = results

      assert result.url =~ "https://hexdocs.pm/"
      assert result.url =~ result.ref
    end

    test "handles special characters in queries" do
      # Test with special characters that might need escaping
      queries = [
        "Module.function/2",
        "@callback handle_*",
        "Phoenix.LiveView",
        "\"exact phrase\""
      ]

      Enum.each(queries, fn query ->
        {:ok, _results, _info} = FulltextSearch.search(query, limit: 1)
        # Should not crash
      end)
    end

    test "pagination works correctly" do
      {:ok, results_page1, info1} = FulltextSearch.search("function", limit: 5, page: 1)
      {:ok, results_page2, info2} = FulltextSearch.search("function", limit: 5, page: 2)

      assert info1.page == 1
      assert info2.page == 2

      # Results should be different between pages
      if length(results_page1) > 0 and length(results_page2) > 0 do
        refute hd(results_page1) == hd(results_page2)
      end
    end
  end

  defp assert_valid_search_result(result) do
    assert is_map(result)
    assert Map.has_key?(result, :package)
    assert Map.has_key?(result, :ref)
    assert Map.has_key?(result, :title)
    assert Map.has_key?(result, :type)
    assert Map.has_key?(result, :url)
    assert Map.has_key?(result, :snippet)
    assert Map.has_key?(result, :matched_tokens)
    assert Map.has_key?(result, :score)
    assert Map.has_key?(result, :proglang)

    assert is_binary(result.package)
    assert is_binary(result.title)
    assert is_binary(result.type)
    assert is_binary(result.url)
    assert is_list(result.matched_tokens)
  end
end
