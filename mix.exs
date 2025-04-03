defmodule HexdocsMcp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/bradleygolden/hexdocs-mcp"
  @license "MIT"

  def project do
    [
      app: :hexdocs_mcp,
      version: @version,
      elixir: ">= 1.16.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "HexDocs MCP",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {HexdocsMcp.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:html2markdown, "~> 0.1"},
      {:text_chunker, "~> 0.3"},
      {:jason, "~> 1.0"},
      {:ollama, "~> 0.8"},
      {:plug, "~> 1.0"},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:ecto_sqlite3, "~> 0.16"},
      {:sqlite_vec, "~> 0.1"},

      # Development and documentation dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:plug_cowboy, "~> 2.0", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp description do
    """
    HexDocs MCP is a project that provides semantic search capabilities for Hex package documentation,
    designed specifically for AI applications. It downloads, processes, and generates embeddings from
    Hex package documentation and provides a Model Context Protocol (MCP) server for searching.
    """
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: [@license],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: ~r/HexdocsMcp\./,
        "MCP Server": ~r/HexdocsMcp\.Server\./
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "hex.build": ["docs", "hex.build"]
    ]
  end
end
