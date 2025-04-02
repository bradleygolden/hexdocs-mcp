defmodule HexMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :hex_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {HexMcp.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:html2markdown, "~> 0.1.5"},
      {:text_chunker, "~> 0.3.2"},
      {:jason, "~> 1.4"},
      {:pythonx, "~> 0.4.0"},
      {:ollama, "~> 0.8.0"},
      {:plug, "~> 1.15"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_sqlite3, "~> 0.16.0"}
    ]
  end
end
