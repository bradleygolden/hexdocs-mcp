defmodule HexdocsMcp.FulltextSearchTest do
  use ExUnit.Case, async: true

  import Mox

  alias HexdocsMcp.Config

  setup :verify_on_exit!

  setup do
    fulltext_search = Config.fulltext_search_module()
    [fulltext_search: fulltext_search]
  end

  describe "search/2" do
    test "searches across all packages", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "GenServer", opts ->
        assert Keyword.get(opts, :limit) == 5

        search_info = %{
          total_found: 150,
          page: 1,
          per_page: 5,
          search_time_ms: 42
        }

        results = [
          %{
            package: "elixir",
            ref: "GenServer.html",
            title: "GenServer",
            type: "module",
            url: "https://hexdocs.pm/elixir/GenServer.html",
            snippet: "A <mark>GenServer</mark> is a process like any other Elixir process...",
            matched_tokens: ["GenServer"],
            score: 0.95,
            proglang: "elixir",
            highlights: [%{field: "doc", snippet: "A <mark>GenServer</mark> is a process"}]
          },
          %{
            package: "elixir",
            ref: "GenServer.html#call/3",
            title: "GenServer.call/3",
            type: "function",
            url: "https://hexdocs.pm/elixir/GenServer.html#call/3",
            snippet: "Makes a synchronous call to the <mark>GenServer</mark>...",
            matched_tokens: ["GenServer"],
            score: 0.90,
            proglang: "elixir",
            highlights: [%{field: "doc", snippet: "call to the <mark>GenServer</mark>"}]
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, search_info} = fulltext_search.search("GenServer", limit: 5)

      assert is_list(results)
      assert length(results) == 2

      assert is_map(search_info)
      assert Map.has_key?(search_info, :total_found)
      assert Map.has_key?(search_info, :page)
      assert Map.has_key?(search_info, :per_page)
      assert Map.has_key?(search_info, :search_time_ms)

      Enum.each(results, fn result ->
        assert_valid_search_result(result)
      end)
    end

    test "searches within a specific package", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "LiveView", opts ->
        assert Keyword.get(opts, :package) == "phoenix_live_view"
        assert Keyword.get(opts, :limit) == 3

        search_info = %{
          total_found: 25,
          page: 1,
          per_page: 3,
          search_time_ms: 15
        }

        results = [
          %{
            package: "phoenix_live_view",
            ref: "Phoenix.LiveView.html",
            title: "Phoenix.LiveView",
            type: "module",
            url: "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html",
            snippet: "The <mark>LiveView</mark> behaviour defines the server-side...",
            matched_tokens: ["LiveView"],
            score: 0.98,
            proglang: "elixir",
            highlights: [%{field: "title", snippet: "Phoenix.<mark>LiveView</mark>"}]
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, _search_info} = fulltext_search.search("LiveView", package: "phoenix_live_view", limit: 3)

      assert is_list(results)
      assert length(results) == 1

      Enum.each(results, fn result ->
        assert_valid_search_result(result)
        assert result.package =~ "phoenix_live_view"
      end)
    end

    test "searches within a specific package version", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "router", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :version) == "1.7.0"
        assert Keyword.get(opts, :limit) == 3

        search_info = %{
          total_found: 10,
          page: 1,
          per_page: 3,
          search_time_ms: 8
        }

        results = [
          %{
            package: "phoenix-1.7.0",
            ref: "Phoenix.Router.html",
            title: "Phoenix.Router",
            type: "module",
            url: "https://hexdocs.pm/phoenix/1.7.0/Phoenix.Router.html",
            snippet: "Defines a Phoenix <mark>router</mark>...",
            matched_tokens: ["router"],
            score: 0.92,
            proglang: "elixir",
            highlights: [%{field: "doc", snippet: "Phoenix <mark>router</mark>"}]
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, _search_info} =
        fulltext_search.search("router",
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

    test "handles unusual queries", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "xyz_nonexistent_query_abc_123_456_789_unusual", _opts ->
        search_info = %{
          total_found: 0,
          page: 1,
          per_page: 10,
          search_time_ms: 5
        }

        {:ok, [], search_info}
      end)

      {:ok, results, search_info} = fulltext_search.search("xyz_nonexistent_query_abc_123_456_789_unusual", [])

      assert is_list(results)
      assert is_integer(search_info.total_found)
      assert search_info.total_found >= 0
    end

    test "respects limit parameter", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "function", opts ->
        limit = Keyword.get(opts, :limit)
        assert limit == 2

        search_info = %{
          total_found: 1000,
          page: 1,
          per_page: 2,
          search_time_ms: 25
        }

        results = [
          %{
            package: "elixir",
            ref: "Function.html",
            title: "Function",
            type: "module",
            url: "https://hexdocs.pm/elixir/Function.html",
            snippet: "Functions in Elixir...",
            matched_tokens: ["function"],
            score: 0.88,
            proglang: "elixir",
            highlights: []
          },
          %{
            package: "elixir",
            ref: "Kernel.html#function_exported?/3",
            title: "function_exported?/3",
            type: "function",
            url: "https://hexdocs.pm/elixir/Kernel.html#function_exported?/3",
            snippet: "Checks if a function is exported...",
            matched_tokens: ["function"],
            score: 0.85,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, search_info} = fulltext_search.search("function", limit: 2)

      assert length(results) <= 2
      assert search_info.per_page == 2
    end

    test "includes highlights in results", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "Enum.map", opts ->
        assert Keyword.get(opts, :limit) == 1

        search_info = %{
          total_found: 50,
          page: 1,
          per_page: 1,
          search_time_ms: 10
        }

        results = [
          %{
            package: "elixir",
            ref: "Enum.html#map/2",
            title: "Enum.map/2",
            type: "function",
            url: "https://hexdocs.pm/elixir/Enum.html#map/2",
            snippet:
              "Returns a list where each element is the result of invoking fun on each corresponding element of enumerable.",
            matched_tokens: ["Enum", "map"],
            score: 0.99,
            proglang: "elixir",
            highlights: [
              %{field: "title", snippet: "<mark>Enum.map</mark>/2"},
              %{field: "doc", snippet: "invoking fun on each"}
            ]
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, _} = fulltext_search.search("Enum.map", limit: 1)

      assert length(results) > 0
      [result | _] = results

      assert Map.has_key?(result, :snippet)
      assert Map.has_key?(result, :highlights)
      assert is_list(result.highlights)
    end

    test "builds correct URLs", %{fulltext_search: fulltext_search} do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "GenServer", opts ->
        assert Keyword.get(opts, :limit) == 1

        search_info = %{
          total_found: 10,
          page: 1,
          per_page: 1,
          search_time_ms: 8
        }

        results = [
          %{
            package: "elixir",
            ref: "GenServer.html",
            title: "GenServer",
            type: "module",
            url: "https://hexdocs.pm/elixir/GenServer.html",
            snippet: "GenServer behaviour",
            matched_tokens: ["GenServer"],
            score: 0.95,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results, _} = fulltext_search.search("GenServer", limit: 1)

      assert length(results) > 0
      [result | _] = results

      assert result.url =~ "https://hexdocs.pm/"
      assert result.url =~ result.ref
    end

    test "handles special characters in queries", %{fulltext_search: fulltext_search} do
      # Test with special characters that might need escaping
      queries = [
        "Module.function/2",
        "@callback handle_*",
        "Phoenix.LiveView",
        "\"exact phrase\""
      ]

      expect(HexdocsMcp.MockFulltextSearch, :search, length(queries), fn _query, opts ->
        assert Keyword.get(opts, :limit) == 1

        search_info = %{
          total_found: 0,
          page: 1,
          per_page: 1,
          search_time_ms: 5
        }

        {:ok, [], search_info}
      end)

      Enum.each(queries, fn query ->
        {:ok, _results, _info} = fulltext_search.search(query, limit: 1)
        # Should not crash
      end)
    end

    test "pagination works correctly", %{fulltext_search: fulltext_search} do
      HexdocsMcp.MockFulltextSearch
      |> expect(:search, fn "function", opts ->
        page = Keyword.get(opts, :page, 1)
        limit = Keyword.get(opts, :limit, 5)

        assert page == 1
        assert limit == 5

        search_info = %{
          total_found: 100,
          page: 1,
          per_page: 5,
          search_time_ms: 20
        }

        results = [
          %{
            package: "elixir-page1",
            ref: "Function1.html",
            title: "Function Page 1",
            type: "module",
            url: "https://hexdocs.pm/elixir/Function1.html",
            snippet: "First page result",
            matched_tokens: ["function"],
            score: 0.9,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)
      |> expect(:search, fn "function", opts ->
        page = Keyword.get(opts, :page, 1)
        limit = Keyword.get(opts, :limit, 5)

        assert page == 2
        assert limit == 5

        search_info = %{
          total_found: 100,
          page: 2,
          per_page: 5,
          search_time_ms: 20
        }

        results = [
          %{
            package: "elixir-page2",
            ref: "Function2.html",
            title: "Function Page 2",
            type: "module",
            url: "https://hexdocs.pm/elixir/Function2.html",
            snippet: "Second page result",
            matched_tokens: ["function"],
            score: 0.85,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      {:ok, results_page1, info1} = fulltext_search.search("function", limit: 5, page: 1)
      {:ok, results_page2, info2} = fulltext_search.search("function", limit: 5, page: 2)

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
