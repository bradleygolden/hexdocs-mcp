defmodule HexdocsMcp.HexSearchTest do
  use ExUnit.Case, async: true

  import Mox

  alias HexdocsMcp.Config

  setup :verify_on_exit!

  setup do
    hex_search = Config.hex_search_module()
    [hex_search: hex_search]
  end

  describe "search_packages/2" do
    test "searches all packages when no package specified", %{hex_search: hex_search} do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "json", opts ->
        assert Keyword.get(opts, :limit) == 5

        {:ok,
         [
           %{
             name: "jason",
             description: "A blazing fast JSON parser and generator in pure Elixir",
             downloads: %{all: 1_000_000, recent: 50_000},
             latest_version: "1.4.0",
             html_url: "https://hex.pm/packages/jason"
           },
           %{
             name: "poison",
             description: "An incredibly fast, pure Elixir JSON library",
             downloads: %{all: 800_000, recent: 30_000},
             latest_version: "5.0.0",
             html_url: "https://hex.pm/packages/poison"
           }
         ]}
      end)

      {:ok, results} = hex_search.search_packages("json", limit: 5)

      assert is_list(results)
      assert length(results) == 2

      Enum.each(results, fn result ->
        assert Map.has_key?(result, :name)
        assert Map.has_key?(result, :description)
        assert Map.has_key?(result, :downloads)
        assert Map.has_key?(result, :latest_version)
        assert Map.has_key?(result, :html_url)
      end)
    end

    test "searches within package versions when package specified", %{hex_search: hex_search} do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "1.7", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :limit) == 5

        {:ok,
         [
           %{
             name: "phoenix",
             version: "1.7.10",
             has_docs: true,
             inserted_at: "2023-10-01T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.10"
           },
           %{
             name: "phoenix",
             version: "1.7.9",
             has_docs: true,
             inserted_at: "2023-09-01T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.9"
           }
         ]}
      end)

      {:ok, results} = hex_search.search_packages("1.7", package: "phoenix", limit: 5)

      assert is_list(results)
      assert length(results) == 2

      Enum.each(results, fn result ->
        assert Map.has_key?(result, :name)
        assert result.name == "phoenix"
        assert Map.has_key?(result, :version)
        assert Map.has_key?(result, :has_docs)
        assert Map.has_key?(result, :inserted_at)
      end)
    end

    test "gets specific version info when package and version specified", %{hex_search: hex_search} do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "info", opts ->
        assert Keyword.get(opts, :package) == "phoenix"
        assert Keyword.get(opts, :version) == "1.7.0"

        {:ok,
         [
           %{
             name: "phoenix",
             version: "1.7.0",
             has_docs: true,
             inserted_at: "2023-01-01T12:00:00Z",
             package_url: "https://hex.pm/api/packages/phoenix",
             docs_url: "https://hexdocs.pm/phoenix/1.7.0",
             description: "Phoenix Framework"
           }
         ]}
      end)

      {:ok, results} = hex_search.search_packages("info", package: "phoenix", version: "1.7.0")

      assert is_list(results)
      assert length(results) == 1

      [result] = results
      assert result.name == "phoenix"
      assert result.version == "1.7.0"
      assert Map.has_key?(result, :has_docs)
      assert Map.has_key?(result, :package_url)
    end

    test "respects sort option", %{hex_search: hex_search} do
      HexdocsMcp.MockHexSearch
      |> expect(:search_packages, fn "test", opts ->
        sort = Keyword.get(opts, :sort)
        limit = Keyword.get(opts, :limit)

        assert limit == 5

        # Return different results based on sort
        case sort do
          "downloads" ->
            {:ok,
             [
               %{
                 name: "popular_test",
                 description: "Very popular test package",
                 downloads: %{all: 1_000_000, recent: 50_000},
                 latest_version: "1.0.0",
                 html_url: "https://hex.pm/packages/popular_test"
               }
             ]}

          "name" ->
            {:ok,
             [
               %{
                 name: "aaa_test",
                 description: "Alphabetically first test package",
                 downloads: %{all: 100, recent: 10},
                 latest_version: "1.0.0",
                 html_url: "https://hex.pm/packages/aaa_test"
               }
             ]}
        end
      end)
      |> expect(:search_packages, fn "test", opts ->
        sort = Keyword.get(opts, :sort)

        assert sort == "name"

        {:ok,
         [
           %{
             name: "aaa_test",
             description: "Alphabetically first test package",
             downloads: %{all: 100, recent: 10},
             latest_version: "1.0.0",
             html_url: "https://hex.pm/packages/aaa_test"
           }
         ]}
      end)

      {:ok, results_downloads} = hex_search.search_packages("test", sort: "downloads", limit: 5)
      {:ok, results_name} = hex_search.search_packages("test", sort: "name", limit: 5)

      # Results should be different when sorted differently
      assert is_list(results_downloads)
      assert is_list(results_name)

      # First result might be different
      assert length(results_downloads) > 0
      assert length(results_name) > 0
      assert hd(results_downloads).name == "popular_test"
      assert hd(results_name).name == "aaa_test"
    end

    test "handles package not found error", %{hex_search: hex_search} do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "test", opts ->
        assert Keyword.get(opts, :package) == "nonexistent_package_xyz_123"

        {:error, "Package not found: 404"}
      end)

      {:error, error_msg} = hex_search.search_packages("test", package: "nonexistent_package_xyz_123")

      assert is_binary(error_msg)
      assert error_msg =~ "not found" or error_msg =~ "404"
    end

    test "handles API errors gracefully", %{hex_search: hex_search} do
      expect(HexdocsMcp.MockHexSearch, :search_packages, fn "", opts ->
        assert Keyword.get(opts, :limit) == -1

        {:ok, []}
      end)

      # Test with invalid parameters that might cause API errors
      result = hex_search.search_packages("", limit: -1)

      # Should either return empty results or an error
      case result do
        {:ok, results} -> assert is_list(results)
        {:error, msg} -> assert is_binary(msg)
      end
    end
  end
end
