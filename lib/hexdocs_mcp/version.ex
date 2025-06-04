defmodule HexdocsMcp.Version do
  @moduledoc """
  Utilities for semantic version comparison and handling.
  """

  @doc """
  Compares two semantic versions.

  Returns:
  - `:gt` if version1 > version2
  - `:lt` if version1 < version2
  - `:eq` if version1 == version2

  ## Examples

      iex> HexdocsMcp.Version.compare("3.5.10", "3.5.9")
      :gt

      iex> HexdocsMcp.Version.compare("3.5.9", "3.5.10")
      :lt

      iex> HexdocsMcp.Version.compare("3.5.9", "3.5.9")
      :eq

      iex> HexdocsMcp.Version.compare("1.0.0-rc.1", "1.0.0")
      :lt

      iex> HexdocsMcp.Version.compare("latest", "3.5.9")
      :eq

      iex> HexdocsMcp.Version.compare("3.5.9", "latest")
      :eq
  """
  def compare("latest", _), do: :eq
  def compare(_, "latest"), do: :eq
  def compare(v1, v2) when v1 == v2, do: :eq

  def compare(v1, v2) do
    case {parse_version(v1), parse_version(v2)} do
      {{:ok, parsed1}, {:ok, parsed2}} ->
        Version.compare(parsed1, parsed2)

      _ ->
        cond do
          v1 > v2 -> :gt
          v1 < v2 -> :lt
          true -> :eq
        end
    end
  end

  @doc """
  Finds the latest version from a list of versions.

  ## Examples

      iex> HexdocsMcp.Version.find_latest(["3.5.9", "3.5.10", "3.5.2"])
      "3.5.10"

      iex> HexdocsMcp.Version.find_latest(["1.0.0-rc.1", "1.0.0", "0.9.0"])
      "1.0.0"

      iex> HexdocsMcp.Version.find_latest(["latest"])
      "latest"

      iex> HexdocsMcp.Version.find_latest([])
      nil
  """
  def find_latest([]), do: nil
  def find_latest(["latest"]), do: "latest"

  def find_latest(versions) when is_list(versions) do
    versions
    |> Enum.filter(&(&1 != "latest"))
    |> case do
      [] ->
        nil

      filtered_versions ->
        Enum.max_by(filtered_versions, &normalize_for_sorting/1, fn v1, v2 ->
          compare(v1, v2) != :lt
        end)
    end
  end

  @doc """
  Groups search results by package and filters to only the latest version of each.

  ## Examples

      iex> results = [
      ...>   %{metadata: %{package: "ash", version: "3.5.9"}},
      ...>   %{metadata: %{package: "ash", version: "3.5.10"}},
      ...>   %{metadata: %{package: "phoenix", version: "1.7.0"}}
      ...> ]
      iex> HexdocsMcp.Version.filter_latest_versions(results)
      [
        %{metadata: %{package: "ash", version: "3.5.10"}},
        %{metadata: %{package: "phoenix", version: "1.7.0"}}
      ]
  """
  def filter_latest_versions(results) do
    results
    |> Enum.group_by(& &1.metadata.package)
    |> Enum.flat_map(fn {_package, package_results} ->
      by_version = Enum.group_by(package_results, & &1.metadata.version)
      versions = Map.keys(by_version)
      latest_version = find_latest(versions)
      Map.get(by_version, latest_version, [])
    end)
  end

  defp parse_version(version) do
    case Version.parse(version) do
      {:ok, _} = result -> result
      :error -> parse_with_fallback(version)
    end
  end

  defp parse_with_fallback(version) do
    cleaned = version |> String.split("-") |> List.first()
    Version.parse(cleaned)
  end

  defp normalize_for_sorting(version) do
    version
  end
end
