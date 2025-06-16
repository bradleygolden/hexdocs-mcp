defmodule HexdocsMcp.CLI.FulltextSearchTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import Mox

  alias HexdocsMcp.CLI.FulltextSearch

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [system_command: system_command]
  end

  describe "fulltext_search command" do
    test "searching across all packages" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "GenServer", opts ->
        assert Keyword.get(opts, :limit) == 3
        assert Keyword.get(opts, :package) == nil
        assert Keyword.get(opts, :version) == nil

        search_info = %{
          total_found: 150,
          page: 1,
          per_page: 3,
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
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "GenServer", "--limit", "3"])
        end)

      assert output =~ "Searching HexDocs in all packages for \"GenServer\""
      assert output =~ "Found 150 results (showing 2)"
      assert output =~ "GenServer"
      assert output =~ "Package: elixir"
      assert output =~ "Type: module"
      assert output =~ "Type: function"
      assert output =~ "Match:"
      assert output =~ "URL: https://hexdocs.pm/"
    end

    test "searching within a specific package" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "LiveView", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :limit) == 3

        search_info = %{
          total_found: 25,
          page: 1,
          per_page: 3,
          search_time_ms: 15
        }

        results = [
          %{
            package: "phoenix",
            ref: "Phoenix.LiveView.html",
            title: "Phoenix.LiveView",
            type: "module",
            url: "https://hexdocs.pm/phoenix/Phoenix.LiveView.html",
            snippet: "The <mark>LiveView</mark> behaviour defines...",
            matched_tokens: ["LiveView"],
            score: 0.98,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["phoenix", "--query", "LiveView", "--limit", "3"])
        end)

      assert output =~ "Searching HexDocs in phoenix for \"LiveView\""
      assert output =~ "Found 25 results (showing 1)"
      assert output =~ "Phoenix.LiveView"
      assert output =~ "Package: phoenix"
      assert output =~ "Type: module"
    end

    test "searching within a specific package version" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "router", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :version) == "1.7.14"
        assert Keyword.get(opts, :limit) == 3

        search_info = %{
          total_found: 10,
          page: 1,
          per_page: 3,
          search_time_ms: 8
        }

        results = [
          %{
            package: "phoenix-1.7.14",
            ref: "Phoenix.Router.html",
            title: "Phoenix.Router",
            type: "module",
            url: "https://hexdocs.pm/phoenix/1.7.14/Phoenix.Router.html",
            snippet: "Defines a Phoenix <mark>router</mark>...",
            matched_tokens: ["router"],
            score: 0.92,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["phoenix", "1.7.14", "--query", "router", "--limit", "3"])
        end)

      assert output =~ "Searching HexDocs in phoenix v1.7.14 for \"router\""
      assert output =~ "Found 10 results (showing 1)"
      assert output =~ "Phoenix.Router"
      assert output =~ "Package: phoenix-1.7.14"
    end

    test "handles unusual query" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "xyz_nonexistent_query_abc_123_456_789", _opts ->
        search_info = %{
          total_found: 0,
          page: 1,
          per_page: 10,
          search_time_ms: 5
        }

        {:ok, [], search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "xyz_nonexistent_query_abc_123_456_789"])
        end)

      assert output =~ "Searching HexDocs"
      assert output =~ "No results found for \"xyz_nonexistent_query_abc_123_456_789\""
    end

    test "displays query syntax in help", %{system_command: system_command} do
      output =
        capture_io(fn ->
          FulltextSearch.main(["--help"])
        end)

      assert output =~ "Usage: #{system_command} fulltext_search"
      assert output =~ "Performs full-text search on HexDocs documentation using Typesense"
      assert output =~ "Query Syntax:"
      assert output =~ "Basic search:"
      assert output =~ "Exact phrase:"
      assert output =~ "AND operator:"
      assert output =~ "OR operator:"
      assert output =~ "Exclude terms:"
      assert output =~ "Examples:"
    end

    test "requires query parameter" do
      output =
        capture_io(fn ->
          FulltextSearch.main([])
        end)

      assert output =~ "Usage:"
      assert output =~ "--query"
    end

    test "supports AND operator in query" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "Phoenix AND LiveView", opts ->
        assert Keyword.get(opts, :limit) == 2

        search_info = %{
          total_found: 5,
          page: 1,
          per_page: 2,
          search_time_ms: 10
        }

        results = [
          %{
            package: "phoenix_live_view",
            ref: "Phoenix.LiveView.html",
            title: "Phoenix.LiveView",
            type: "module",
            url: "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html",
            snippet: "<mark>Phoenix</mark> <mark>LiveView</mark> enables rich, real-time user experiences...",
            matched_tokens: ["Phoenix", "LiveView"],
            score: 0.99,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "Phoenix AND LiveView", "--limit", "2"])
        end)

      assert output =~ "Searching HexDocs in all packages for \"Phoenix AND LiveView\""
      assert output =~ "Phoenix.LiveView"
    end

    test "supports exact phrase search" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "\"handle_event\"", opts ->
        assert Keyword.get(opts, :limit) == 2

        search_info = %{
          total_found: 10,
          page: 1,
          per_page: 2,
          search_time_ms: 8
        }

        results = [
          %{
            package: "phoenix_live_view",
            ref: "Phoenix.LiveView.html#handle_event/3",
            title: "handle_event/3",
            type: "callback",
            url: "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#handle_event/3",
            snippet: "The <mark>handle_event</mark> callback is invoked when...",
            matched_tokens: ["handle_event"],
            score: 0.95,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "\"handle_event\"", "--limit", "2"])
        end)

      assert output =~ "Searching HexDocs in all packages for"
      assert output =~ "handle_event"
      assert output =~ "handle_event/3"
    end

    test "supports exclude operator" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "Phoenix -test", opts ->
        assert Keyword.get(opts, :limit) == 2

        search_info = %{
          total_found: 50,
          page: 1,
          per_page: 2,
          search_time_ms: 15
        }

        results = [
          %{
            package: "phoenix",
            ref: "Phoenix.html",
            title: "Phoenix",
            type: "module",
            url: "https://hexdocs.pm/phoenix/Phoenix.html",
            snippet: "<mark>Phoenix</mark> is a web framework for Elixir...",
            matched_tokens: ["Phoenix"],
            score: 0.90,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "Phoenix -test", "--limit", "2"])
        end)

      assert output =~ "Searching HexDocs in all packages for \"Phoenix -test\""
      assert output =~ "Phoenix"
      # The search query itself contains "test", so we can't refute it entirely
    end

    test "respects limit parameter" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "function", opts ->
        assert Keyword.get(opts, :limit) == 1

        search_info = %{
          total_found: 1000,
          page: 1,
          per_page: 1,
          search_time_ms: 20
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
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "function", "--limit", "1"])
        end)

      assert output =~ "Found 1000 results (showing 1)"
      # Count the number of URLs in output - should be exactly 1
      url_count = output |> String.split("\n") |> Enum.count(&String.contains?(&1, "URL:"))
      assert url_count == 1
    end

    test "shows snippet highlighting" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "GenServer", opts ->
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
            ref: "GenServer.html",
            title: "GenServer",
            type: "module",
            url: "https://hexdocs.pm/elixir/GenServer.html",
            snippet: "A <mark>GenServer</mark> is a process like any other Elixir process...",
            matched_tokens: ["GenServer"],
            score: 0.95,
            proglang: "elixir",
            highlights: []
          }
        ]

        {:ok, results, search_info}
      end)

      output =
        capture_io(fn ->
          FulltextSearch.main(["--query", "GenServer", "--limit", "1"])
        end)

      assert output =~ "Match:"
      # The CLI should replace <mark> tags with ANSI formatting
      refute output =~ "<mark>"
      refute output =~ "</mark>"
    end

    test "handles API errors gracefully" do
      expect(HexdocsMcp.MockFulltextSearch, :search, fn "test", _opts ->
        {:error, "Search API is temporarily unavailable"}
      end)

      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            FulltextSearch.main(["--query", "test"])
          end)
        end)

      assert output =~ "Search failed: Search API is temporarily unavailable"
    end
  end
end
