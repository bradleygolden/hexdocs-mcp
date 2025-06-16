defmodule HexdocsMcp.CLI.HexSearchTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import Mox

  alias HexdocsMcp.CLI.HexSearch

  setup :verify_on_exit!

  setup do
    system_command = HexdocsMcp.Config.system_command()
    [system_command: system_command]
  end

  describe "hex_search command" do
    test "searching for packages" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "json", opts ->
        assert Keyword.get(opts, :limit) == 3

        {:ok,
         [
           %{
             name: "jason",
             description: "A blazing fast JSON parser and generator in pure Elixir",
             downloads: %{all: 1_234_567, recent: 50_000},
             latest_version: "1.4.0",
             html_url: "https://hex.pm/packages/jason",
             docs_url: "https://hexdocs.pm/jason"
           },
           %{
             name: "poison",
             description: "An incredibly fast, pure Elixir JSON library",
             downloads: %{all: 987_654, recent: 30_000},
             latest_version: "5.0.0",
             html_url: "https://hex.pm/packages/poison"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["--query", "json", "--limit", "3"])
        end)

      assert output =~ "Searching Hex.pm packages matching \"json\""
      assert output =~ "Found 2 results"
      assert output =~ "jason"
      assert output =~ "poison"
      assert output =~ "Downloads:"
      assert output =~ "1.2M total"
      assert output =~ "50.0K recent"
      assert output =~ "Hex:"
    end

    test "searching within a package's versions" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "1.7", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :limit) == 3

        {:ok,
         [
           %{
             name: "phoenix",
             version: "1.7.10",
             description: "Phoenix Framework",
             has_docs: true,
             inserted_at: "2023-10-15T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.10",
             url: "https://hex.pm/api/packages/phoenix/releases/1.7.10"
           },
           %{
             name: "phoenix",
             version: "1.7.9",
             description: "Phoenix Framework",
             has_docs: true,
             inserted_at: "2023-09-01T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.9",
             url: "https://hex.pm/api/packages/phoenix/releases/1.7.9"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["phoenix", "--query", "1.7", "--limit", "3"])
        end)

      assert output =~ "Searching Hex.pm package phoenix versions matching \"1.7\""
      assert output =~ "Found 2 results"
      assert output =~ "phoenix v1.7.10"
      assert output =~ "phoenix v1.7.9"
      assert output =~ "Has docs: true"
      assert output =~ "Released:"
    end

    test "getting specific package version info" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "info", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :version) == "1.7.0"

        {:ok,
         [
           %{
             name: "phoenix",
             version: "1.7.0",
             description: "Phoenix Framework - Productive. Reliable. Fast.",
             has_docs: true,
             inserted_at: "2023-01-01T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.0",
             url: "https://hex.pm/api/packages/phoenix/releases/1.7.0"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["phoenix", "1.7.0", "--query", "info"])
        end)

      assert output =~ "Searching Hex.pm package phoenix version 1.7.0"
      assert output =~ "phoenix v1.7.0"
      assert output =~ "Phoenix Framework - Productive. Reliable. Fast."
      assert output =~ "Has docs: true"
      assert output =~ "API:"
    end

    test "shows help with --help flag", %{system_command: system_command} do
      output =
        capture_io(fn ->
          HexSearch.main(["--help"])
        end)

      assert output =~ "Usage: #{system_command} hex_search [PACKAGE] [VERSION] [options]"
      assert output =~ "Searches for packages on Hex.pm"
      assert output =~ "Arguments:"
      assert output =~ "Options:"
      assert output =~ "--query QUERY"
      assert output =~ "--sort SORT"
      assert output =~ "--limit LIMIT"
      assert output =~ "Examples:"
    end

    test "shows help with -h flag", %{system_command: system_command} do
      output =
        capture_io(fn ->
          HexSearch.main(["-h"])
        end)

      assert output =~ "Usage: #{system_command} hex_search"
    end

    test "handles no results gracefully" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "xyz_nonexistent_123", _opts ->
        {:ok, []}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["--query", "xyz_nonexistent_123"])
        end)

      assert output =~ "No results found matching \"xyz_nonexistent_123\""
    end

    test "handles API errors gracefully" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "test", _opts ->
        {:error, "API request failed: Connection timeout"}
      end)

      output =
        capture_io(:stderr, fn ->
          capture_io(fn ->
            HexSearch.main(["--query", "test"])
          end)
        end)

      assert output =~ "Search failed: API request failed: Connection timeout"
    end

    test "sorts results by different criteria" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "test", opts ->
        assert Keyword.get(opts, :sort) == "recent"

        {:ok,
         [
           %{
             name: "recent_test",
             description: "Recently updated test package",
             downloads: %{all: 100, recent: 50},
             latest_version: "0.1.0",
             html_url: "https://hex.pm/packages/recent_test"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["--query", "test", "--sort", "recent"])
        end)

      assert output =~ "recent_test"
      assert output =~ "Recently updated test package"
    end

    test "respects custom limit" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "elixir", opts ->
        limit = Keyword.get(opts, :limit)
        assert limit == 5
        # Return exactly 5 results
        results =
          for i <- 1..5 do
            %{
              name: "package_#{i}",
              description: "Test package #{i}",
              downloads: %{all: i * 1000, recent: i * 100},
              latest_version: "1.0.#{i}",
              html_url: "https://hex.pm/packages/package_#{i}"
            }
          end

        {:ok, results}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["--query", "elixir", "--limit", "5"])
        end)

      assert output =~ "Found 5 results"
      assert output =~ "package_1"
      assert output =~ "package_5"
    end

    test "formats large download numbers correctly" do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "popular", _opts ->
        {:ok,
         [
           %{
             name: "super_popular",
             description: "Extremely popular package",
             downloads: %{all: 1_234_567_890, recent: 10_000_000},
             latest_version: "10.0.0",
             html_url: "https://hex.pm/packages/super_popular"
           }
         ]}
      end)

      output =
        capture_io(fn ->
          HexSearch.main(["--query", "popular"])
        end)

      assert output =~ "1.2B total"
      assert output =~ "10.0M recent"
    end
  end
end
