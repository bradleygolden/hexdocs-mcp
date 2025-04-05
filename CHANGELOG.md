# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bradleygolden/hexdocs-mcp/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/bradleygolden/hexdocs-mcp/releases/tag/v0.1.1
[0.1.0]: https://github.com/bradleygolden/hexdocs-mcp/releases/tag/0.1.0 