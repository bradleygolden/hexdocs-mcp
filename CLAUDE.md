# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HexDocs MCP is a project that provides semantic search capabilities for Hex package documentation, designed specifically for AI applications. It downloads, processes, and generates embeddings from Hex package documentation and provides a Model Context Protocol (MCP) server for searching.

## Architecture

### Core Components

1. **Application Entry Points**
   - `HexdocsMcp.Application` - OTP application for development/test environments
   - `HexdocsMcp.CLI` - Main CLI entry point for both Mix task and standalone executable
   - `Mix.Tasks.Hex.Docs.Mcp` - Mix task wrapper

2. **Core Modules**
   - `HexdocsMcp.Embeddings` - Generates and searches vector embeddings
   - `HexdocsMcp.Docs` - Fetches documentation from Hex
   - `HexdocsMcp.Markdown` - Converts HTML to Markdown
   - `HexdocsMcp.Repo` - Ecto repository for SQLite database
   - `HexdocsMcp.Config` - Centralized configuration and dependency injection
   - `HexdocsMcp.Ollama` - Wrapper for Ollama AI integration
   - `HexdocsMcp.MixDeps` - Parses mix.exs dependencies

3. **CLI Modules**
   - `HexdocsMcp.CLI.Fetch` - Implements fetch command
   - `HexdocsMcp.CLI.Search` - Implements search command
   - `HexdocsMcp.CLI.Progress` - Rich progress indicators
   - `HexdocsMcp.CLI.Utils` - Shared CLI utilities

### Data Flow

1. **Document Fetching**: `mix hex.docs fetch` → HTML files
2. **Conversion**: HTML → Markdown using Floki
3. **Chunking**: Markdown → Semantic chunks (2000 chars, 200 overlap)
4. **Embedding**: Chunks → 384-dimensional vectors via Ollama
5. **Storage**: Embeddings → SQLite with vector extension
6. **Search**: Query → Embedding → Vector similarity search

### Database Schema

**embeddings table**:
- `id`: Primary key
- `package`, `version`: Package identification
- `source_file`: Original HTML file path
- `text`: Full chunk text
- `text_snippet`: First 100 chars preview
- `content_hash`: SHA-256 for deduplication
- `url`: Direct documentation link
- `embedding`: 384-dimensional float vector
- `timestamps`: inserted_at, updated_at

Indexes on: `(package, version)`, `(package, version, content_hash)`

### External Dependencies

**Core Dependencies**:
- `text_chunker` - Semantic text chunking
- `ollama` - AI embedding generation
- `ecto_sqlite3` + `sqlite_vec` - Vector database
- `floki` - HTML parsing
- `burrito` - Standalone executable packaging

**MCP Server** (Node.js):
- `@modelcontextprotocol/sdk` - MCP protocol implementation
- Manages Elixir binary lifecycle
- Exposes fetch/search tools to AI assistants

## Build/Run/Test Commands

### Development
- Mix compile: `mix compile`
- Setup dependencies: `mix setup`
- Format code: `mix format`
- Run linter: `mix credo`
- Watch tests: `mix test.watch`

### CLI Commands

**Fetch Command**:
```bash
mix hex.docs.mcp fetch PACKAGE [VERSION] [options]
  --model MODEL    # Ollama model (default: nomic-embed-text)
  --force         # Force re-fetch even if embeddings exist
  --project PATH  # Fetch all deps from mix.exs
  --help, -h      # Show help

# Examples
mix hex.docs.mcp fetch phoenix
mix hex.docs.mcp fetch phoenix 1.7.0 --model all-minilm
mix hex.docs.mcp fetch --project mix.exs --force
```

**Search Command**:
```bash
mix hex.docs.mcp search [PACKAGE] [VERSION] [options]
  --query QUERY   # Search query (required)
  --model MODEL   # Ollama model (default: nomic-embed-text)
  --limit LIMIT   # Max results (default: 3)
  --help, -h      # Show help

# Examples
mix hex.docs.mcp search --query "how to create channels"
mix hex.docs.mcp search phoenix --query "configuration options" --limit 10
```

### Testing
- Run all tests: `mix test`
- Run single test: `mix test test/hexdocs_mcp_test.exs:LINE_NUMBER`
- Run specific module: `mix test test/hexdocs_mcp/embeddings_test.exs`

### Building
- Build docs: `mix docs`
- Build hex package: `mix hex.build`
- Build standalone: `mix release`

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

## Testing Patterns

### Behavior-based Architecture
All external dependencies are wrapped in behaviors for testability:
- `HexdocsMcp.Behaviours.Ollama` - AI service interface
- `HexdocsMcp.Behaviours.Docs` - Documentation fetching
- `HexdocsMcp.Behaviours.Embeddings` - Embedding operations

### Mocking Strategy
- Uses Mox for behavior-based mocks
- Mocks configured in test_helper.exs
- Custom mock implementations for complex scenarios
- Process message testing for internal verification

### Database Testing
- Uses SQL Sandbox for test isolation
- DataCase module for database test setup
- Automatic cleanup between tests
- SQLite vector extension loaded in tests

### CLI Testing
- IO capture for output verification
- Mock injection via application config
- Tests cover success paths, errors, and help output

## Configuration

### Environment Variables
- `HEXDOCS_MCP_DATA_PATH` - Data storage location (default: ~/.hexdocs_mcp)
- `HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL` - Default Ollama model
- `HEXDOCS_MCP_MIX_PROJECT_PATHS` - Comma-separated mix.exs paths

### Application Config
Configuration is centralized in `HexdocsMcp.Config` for:
- Module dependency injection
- Path configuration
- Default values
- Test vs production behavior

## MCP Integration

The project includes a Node.js MCP server that:
1. Downloads and manages the Elixir binary
2. Exposes `fetch` and `search` tools
3. Handles binary updates automatically
4. Communicates via stdio transport

Deploy with: `node dist/index.js` (after `npm run build`)

## Performance Considerations

- **Batch Processing**: Embeddings generated in batches of 10
- **Concurrency**: Max 4 concurrent Ollama requests
- **Deduplication**: Content-based hashing prevents duplicate embeddings
- **Incremental Updates**: Only new/changed content is processed
- **Vector Search**: Efficient similarity search using SQLite vec extension