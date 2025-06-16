defmodule HexdocsMcp.FulltextSearch do
  @moduledoc """
  Functions for searching HexDocs using their full-text search API.
  """

  @behaviour HexdocsMcp.Behaviours.FulltextSearch

  @search_api_base "https://search.hexdocs.pm"

  @doc """
  Performs full-text search on HexDocs using Typesense.

  ## Options
    * `:package` - Optional package name to filter results
    * `:version` - Optional version to filter results (requires :package)
    * `:limit` - Maximum number of results to return. Defaults to 10, max 100.
    * `:type` - Optional document type filter (e.g., "function", "module", "type", "callback")
    * `:page` - Optional page number for pagination. Defaults to 1.
  """
  def search(query, opts \\ []) do
    package = Keyword.get(opts, :package)
    version = Keyword.get(opts, :version)
    limit = min(Keyword.get(opts, :limit, 10), 100)
    type = Keyword.get(opts, :type)
    page = Keyword.get(opts, :page, 1)

    params = %{
      "q" => query,
      "query_by" => "doc,title",
      "per_page" => limit,
      "page" => page,
      # Include more fields in response for better context
      "include_fields" => "title,doc,type,ref,package,proglang",
      # Highlight settings for better snippets
      "highlight_affix_num_tokens" => 10,
      "highlight_full_fields" => "doc"
    }

    # Build filter_by clause
    filters = []

    filters =
      if package && version do
        ["package:=#{package}-#{version}" | filters]
      else
        if package do
          # For package-only filter, we need to match any version of that package
          ["package:#{package}-*" | filters]
        else
          filters
        end
      end

    filters =
      if type do
        ["type:=#{type}" | filters]
      else
        filters
      end

    params =
      if length(filters) > 0 do
        Map.put(params, "filter_by", Enum.join(filters, " && "))
      else
        params
      end

    case Req.get(@search_api_base, params: params) do
      {:ok, %{status: 200, body: %{"hits" => hits, "found" => found} = body}} ->
        results = Enum.map(hits, &format_search_result/1)

        search_info = %{
          total_found: found,
          page: page,
          per_page: limit,
          search_time_ms: Map.get(body, "search_time_ms", 0)
        }

        {:ok, results, search_info}

      {:ok, %{status: 200, body: %{"message" => message}}} ->
        {:error, "Search failed: #{message}"}

      {:ok, %{status: status_code, body: body}} ->
        {:error, "Failed to search HexDocs: HTTP #{status_code} - #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp format_search_result(%{"document" => doc, "highlight" => highlight} = result) do
    %{
      package: doc["package"],
      ref: doc["ref"],
      title: doc["title"],
      type: doc["type"],
      proglang: Map.get(doc, "proglang", "elixir"),
      url: build_doc_url(doc),
      snippet: get_best_snippet(highlight),
      matched_tokens: get_matched_tokens(highlight),
      score: Map.get(result, "text_match", 0),
      highlights: format_highlights(Map.get(result, "highlights", []))
    }
  end

  defp format_highlights(highlights) do
    Enum.map(highlights, fn h ->
      %{
        field: h["field"],
        snippet: h["snippet"],
        matched_tokens: h["matched_tokens"]
      }
    end)
  end

  defp build_doc_url(%{"package" => package, "ref" => ref}) do
    # Extract package name and version from package field (format: "package-version")
    case String.split(package, "-") do
      [pkg_name | version_parts] when version_parts != [] ->
        version = Enum.join(version_parts, "-")
        "https://hexdocs.pm/#{pkg_name}/#{version}/#{ref}"

      _ ->
        "https://hexdocs.pm/#{package}/#{ref}"
    end
  end

  defp get_best_snippet(%{"doc" => %{"snippet" => snippet}}), do: snippet
  defp get_best_snippet(%{"title" => %{"snippet" => snippet}}), do: snippet
  defp get_best_snippet(_), do: ""

  defp get_matched_tokens(highlight) do
    tokens = []

    tokens =
      if doc_tokens = get_in(highlight, ["doc", "matched_tokens"]) do
        tokens ++ doc_tokens
      else
        tokens
      end

    tokens =
      if title_tokens = get_in(highlight, ["title", "matched_tokens"]) do
        tokens ++ title_tokens
      else
        tokens
      end

    Enum.uniq(tokens)
  end
end
