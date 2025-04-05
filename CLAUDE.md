# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Run/Test Commands
- Mix compile: `mix compile`
- Fetch docs (with embedding): `mix hex.docs.mcp fetch PACKAGE [VERSION]`
- Fetch with custom model: `mix hex.docs.mcp fetch --model all-minilm phoenix`
- Force re-fetch docs: `mix hex.docs.mcp fetch --force phoenix`
- Search in embeddings: `mix hex.docs.mcp search --query "query" phoenix`
- Legacy mode (fetch): `mix hex.docs.mcp PACKAGE [VERSION]`
- Legacy mode (search): `mix hex.docs.mcp --query "query" phoenix`
- Run all tests: `mix test`
- Run single test: `mix test test/hexdocs_mcp_test.exs:LINE_NUMBER`
- Format code: `mix format`

## Code Style Guidelines
- **Formatting**: Follow Elixir formatter rules defined in .formatter.exs
- **Naming**: Use snake_case for functions and variables, PascalCase for modules
- **Imports**: Group and alphabetize imports; prefer alias for external modules
- **Documentation**: Use @moduledoc and @doc with examples in doctest format
- **Error Handling**: Use with/else pattern for chained operations that may fail
- **Function Organization**: Private functions follow public functions they support
- **Logging**: Use Logger with appropriate levels (debug, info, error)
- **Module Structure**: Follow conventional mix project structure
- **Types**: Prefer not to document function types using @spec
- **Comments**: Avoid code comments unless absolutely necessary