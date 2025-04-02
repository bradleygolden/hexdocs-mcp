# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Run/Test Commands
- Mix compile: `mix compile`
- Run app (with embedding): `mix hex.mcp PACKAGE [VERSION]`
- Run without embedding: `mix hex.mcp --no-embed PACKAGE [VERSION]`
- Run with custom model: `mix hex.mcp --model all-minilm phoenix`
- SQLite search (default): `mix hex.mcp --search "query" phoenix`
- SQLite search (explicit): `mix hex.mcp --search "query" --sqlite phoenix`
- LanceDB search (legacy): `mix hex.mcp --search "query" --lancedb phoenix`
- Run migrations: `mix ecto.migrate`
- Run all tests: `mix test`
- Run single test: `mix test test/hex_mcp_test.exs:LINE_NUMBER`
- Format code: `mix format`
- Rebuild Rust NIF: `cd native/lancedb && cargo build`

## Code Style Guidelines
- **Formatting**: Follow Elixir formatter rules defined in .formatter.exs
- **Naming**: Use snake_case for functions and variables, PascalCase for modules
- **Imports**: Group and alphabetize imports; prefer alias for external modules
- **Documentation**: Use @moduledoc and @doc with examples in doctest format
- **Error Handling**: Use with/else pattern for chained operations that may fail
- **Function Organization**: Private functions follow public functions they support
- **Logging**: Use Logger with appropriate levels (debug, info, error)
- **Module Structure**: Follow conventional mix project structure
- **Types**: Document function types using @spec when possible