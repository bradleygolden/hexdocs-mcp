defmodule HexdocsMcp.VersionTest do
  use ExUnit.Case, async: true

  alias HexdocsMcp.Version

  describe "compare/2" do
    test "compares major versions" do
      assert Version.compare("2.0.0", "1.0.0") == :gt
      assert Version.compare("1.0.0", "2.0.0") == :lt
      assert Version.compare("1.0.0", "1.0.0") == :eq
    end

    test "compares minor versions" do
      assert Version.compare("1.2.0", "1.1.0") == :gt
      assert Version.compare("1.1.0", "1.2.0") == :lt
      assert Version.compare("1.1.0", "1.1.0") == :eq
    end

    test "compares patch versions" do
      assert Version.compare("1.0.2", "1.0.1") == :gt
      assert Version.compare("1.0.1", "1.0.2") == :lt
      assert Version.compare("1.0.1", "1.0.1") == :eq
    end

    test "compares complex versions" do
      assert Version.compare("3.5.10", "3.5.9") == :gt
      assert Version.compare("3.5.9", "3.5.10") == :lt
    end

    test "handles pre-release versions" do
      assert Version.compare("1.0.0-rc.1", "1.0.0") == :lt
      assert Version.compare("1.0.0", "1.0.0-rc.1") == :gt
      assert Version.compare("1.0.0-rc.2", "1.0.0-rc.1") == :gt
    end

    test "handles latest version" do
      assert Version.compare("latest", "3.5.9") == :eq
      assert Version.compare("3.5.9", "latest") == :eq
      assert Version.compare("latest", "latest") == :eq
    end

    test "handles invalid versions with string comparison" do
      assert Version.compare("invalid", "1.0.0") == :gt
      assert Version.compare("1.0.0", "invalid") == :lt
    end
  end

  describe "find_latest/1" do
    test "finds latest from simple versions" do
      assert Version.find_latest(["1.0.0", "2.0.0", "1.5.0"]) == "2.0.0"
      assert Version.find_latest(["3.5.9", "3.5.10", "3.5.2"]) == "3.5.10"
    end

    test "handles pre-release versions" do
      assert Version.find_latest(["1.0.0-rc.1", "1.0.0", "0.9.0"]) == "1.0.0"
      assert Version.find_latest(["2.0.0-beta", "2.0.0-alpha"]) == "2.0.0-beta"
      assert Version.find_latest(["2.0.0-beta", "1.9.0", "2.0.0-alpha"]) == "2.0.0-beta"
    end

    test "handles latest version" do
      assert Version.find_latest(["latest"]) == "latest"
      assert Version.find_latest(["1.0.0", "latest", "2.0.0"]) == "2.0.0"
    end

    test "handles empty list" do
      assert Version.find_latest([]) == nil
    end

    test "handles single version" do
      assert Version.find_latest(["1.0.0"]) == "1.0.0"
    end
  end

  describe "filter_latest_versions/1" do
    test "filters to latest version per package" do
      results = [
        %{metadata: %{package: "ash", version: "3.5.9"}, score: 0.5},
        %{metadata: %{package: "ash", version: "3.5.10"}, score: 0.6},
        %{metadata: %{package: "ash", version: "3.5.2"}, score: 0.4},
        %{metadata: %{package: "phoenix", version: "1.7.0"}, score: 0.7},
        %{metadata: %{package: "phoenix", version: "1.6.0"}, score: 0.3}
      ]

      filtered = Version.filter_latest_versions(results)

      assert length(filtered) == 2

      ash_results = Enum.filter(filtered, &(&1.metadata.package == "ash"))
      assert length(ash_results) == 1
      assert hd(ash_results).metadata.version == "3.5.10"

      phoenix_results = Enum.filter(filtered, &(&1.metadata.package == "phoenix"))
      assert length(phoenix_results) == 1
      assert hd(phoenix_results).metadata.version == "1.7.0"
    end

    test "preserves all results for the latest version" do
      results = [
        %{metadata: %{package: "ash", version: "3.5.9", text: "result1"}, score: 0.5},
        %{metadata: %{package: "ash", version: "3.5.10", text: "result2"}, score: 0.6},
        %{metadata: %{package: "ash", version: "3.5.10", text: "result3"}, score: 0.4}
      ]

      filtered = Version.filter_latest_versions(results)

      assert length(filtered) == 2
      assert Enum.all?(filtered, &(&1.metadata.version == "3.5.10"))
    end

    test "handles empty results" do
      assert Version.filter_latest_versions([]) == []
    end

    test "handles single result" do
      results = [%{metadata: %{package: "ash", version: "3.5.9"}, score: 0.5}]
      assert Version.filter_latest_versions(results) == results
    end
  end
end
