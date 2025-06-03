# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Improved HexDocs HTML parsing to better filter navigation elements
  - Extracts main content area (`<main>`, `#content`, `.content-inner`, etc.) to focus on documentation
  - Filters out sidebar navigation by both class and ID attributes
  - Preserves actual documentation content while removing repetitive navigation
  - Reduces noise in search results from sidebar elements appearing in embeddings

## [0.5.0] - 2025-01-06

### Added
- Added URL field to embedding metadata
  - Allows LLMs to optionally fetch the original documentation URL
  - Improves context retrieval with direct source references
  - **Note:** Embeddings created before this update will have null URL values and won't be shown to the LLM
  - To add URLs to existing embeddings:
    - CLI: Run `mix hex.docs.mcp fetch PACKAGE --force`
    - MCP: Ask `Please fetch the latest <PACKAGE> hexdocs with the force option`
- Enhanced CLAUDE.md with comprehensive architecture documentation ([#9](https://github.com/bradleygolden/hexdocs-mcp/pull/9)) - Thanks @dvic!

### Fixed
- Fixed latest version detection on fetch ([#7](https://github.com/bradleygolden/hexdocs-mcp/issues/7))
  - Now correctly detects and fetches the latest version when version is not specified
  - Uses Hex.pm API for accurate version resolution
- Fixed postinstall script to handle missing dist directory during initial setup ([#8](https://github.com/bradleygolden/hexdocs-mcp/pull/8)) - Thanks @dvic!

## [0.4.1]

### Fixed
- Fixed VSCode warning issues by adding tool descriptions to MCP server tool registration ([#6](https://github.com/bradleygolden/hexdocs-mcp/issues/6))

## [0.4.0]

### Added
- Added content hashing for incremental embedding refresh
  - Automatically reuses existing embeddings for unchanged documentation chunks
  - Only generates new embeddings for modified chunks
  - Improves performance for packages with minor documentation changes
  - Maintains embedding consistency while reducing computational cost
  - Hash generation uses SHA-256 for reliable content identification

## [0.3.1]

### Fixed
- Fixed SQLite vec extension not being properly loaded in binaries, resolving "no such function: vec_f32" error ([#4](https://github.com/bradleygolden/hexdocs-mcp/issues/4))

## [0.3.0]

### Added
- Added Styler formatter plugin for consistent code style enforcement
- Added Credo static code analyzer for code quality enforcement
- Support for `HEXDOCS_MCP_MIX_PROJECT_PATHS` environment variable as an alternative to `--project` flag
  - Allows setting multiple comma-separated paths to mix.exs files
  - First valid path is used when fetching package documentation
  - Simplifies workflow by not having to specify project path for every command
- Made package name optional for search command allowing search across all packages
  - In CLI: `hexdocs_mcp search --query "your query"` now searches across all indexed packages
  - In MCP server: `packageName` parameter is now optional in the search tool

### Changed
- Updated code to comply with Credo rules

## [0.2.0]

## Migration Guide

### Upgrading to 0.2.0

The main change in 0.2.0 is that you no longer need to add hexdocs_mcp as a dependency in your project's `mix.exs`. Instead, the functionality is now provided through pre-built binaries that are automatically downloaded when using the MCP server.

1. Remove the following from your `mix.exs`:
```elixir
{:hexdocs_mcp, "~> 0.1", only: :dev, runtime: false}
```

2. If you've updated any dependencies to be available in `:dev` (like `:floki`), you can revert those changes if they're no longer needed for other purposes.

3. Ensure your MCP client configuration is set up correctly (this should already be the case if you were using version 0.1.x):
```json
{
  "mcpServers": {
    "hexdocs-mcp": {
      "command": "npx",
      "args": [
        "-y",
        "hexdocs-mcp"
      ]
    }
  }
}
```

### Added
- Download sqlite-vec extension on startup to ensure it's available
- Add `--force` option to re-fetch and update embeddings for existing packages
- Add cache support for embeddings (skips re-fetching if already exists)
- Add behavior interfaces for better mocking in tests
- Added fetch command to MCP server to automatically fetch package documentation when needed

### Changed
- Removed need to manually add hexdocs_mcp to your project
  - Project is still available on hex but now includes pre-built binaries for each platform using burrito
  - Added checksums and GPG signing for binary security
  - No need to worry about Elixir version or maintaining project dependencies
  - MCP server can be used across multiple projects easily
- Migrated all vector search logic from TypeScript to Elixir binaries
  - TypeScript server now acts as a wrapper for the Elixir binary for improved portability
- Refactored codebase for improved readability, testability, and maintainability

## [0.1.2]

### Changed
- Simplified installation process - now installable via npx
- Updated MCP server response format to match latest MCP standard

### Removed
- Removed `list_packages` tool from MCP server

## [0.1.1] - 2024-04-04

### Changed
- Published NPM package to align version with Hex package

## [0.1.0] - 2024-04-03

Initial release of HexDocs MCP, providing semantic search capabilities for Hex package documentation.

### Added

#### Elixir Package
- `mix hex.docs.mcp fetch` command to:
  - Download Hex package documentation
  - Convert HTML docs to consolidated markdown
  - Create semantic text chunks
  - Generate embeddings using Ollama
  - Automatically initialize SQLite database with vector search capabilities when needed
- `mix hex.docs.mcp search` command for semantic search in embeddings
- Support for custom embedding models via `--model` flag
- Configurable data storage location via `HEXDOCS_MCP_PATH` environment variable

#### TypeScript MCP Server
- Model Context Protocol (MCP) server implementation
- Integration with MCP-compatible clients (Cursor, Claude Desktop App, etc.)
- Vector similarity search using SQLite database
- Automatic database initialization on startup

### Dependencies
- Requires Elixir 1.16 or later
- Requires Node.js 22 or later
- Requires Ollama for embedding generation
  - Default model: `nomic-embed-text`
  - Support for alternative models like `all-minilm`

[Unreleased]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/bradleygolden/hexdocs-mcp/releases/tag/v0.1.2
[0.1.1]: https://github.com/bradleygolden/hexdocs-mcp/releases/tag/v0.1.1
[0.1.0]: https://github.com/bradleygolden/hexdocs-mcp/releases/tag/0.1.0