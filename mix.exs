defmodule HexdocsMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexdocs_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:html2markdown, "~> 0.1.5"},
      {:text_chunker, "~> 0.3.2"},
      {:jason, "~> 1.4"},
      {:ollama, "~> 0.8.0"},
      {:plug, "~> 1.15"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.16.0"},
      {:sqlite_vec, "~> 0.1.0"},
      {:plug_cowboy, "~> 2.6", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
