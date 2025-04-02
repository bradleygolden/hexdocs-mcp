# HexdocsMcp

HexdocsMcp is a tool that downloads Hex package documentation, converts it to markdown format, and creates semantic text chunks suitable for embedding in vector databases. It downloads the HTML documentation using the `mix hex.docs` task, converts all HTML files to a single markdown file, and then creates semantically meaningful chunks with metadata.

## Components

The project consists of two main components:

1. **Elixir HexdocsMcp** - Downloads, processes and embeds Hex package documentation
2. **MCP Server** - A TypeScript implementation of the Model Context Protocol (MCP) that provides a searchable interface to the embeddings

## Installation

```elixir
def deps do
  [
    {:hexdocs_mcp, "~> 0.1.0"}
  ]
end
```

### Requirements

- [Ollama](https://ollama.ai) - Required for generating embeddings
  - Run `ollama pull nomic-embed-text` to download the recommended embedding model
  - Ensure Ollama is running before using hexdocs_mcp with embedding features

## Usage

### Configuration

By default, HexdocsMcp stores all data in `~/.hexdocs_mcp` in the user's home directory. You can change this location by setting the `HEXDOCS_MCP_PATH` environment variable:

```bash
# Example: Set custom storage location
export HEXDOCS_MCP_PATH=/path/to/custom/directory
```

Both the Elixir module and MCP server will use this configuration to find and store data.

### Elixir HexdocsMcp

The command requires explicit subcommands: `fetch` or `search`.

Fetch documentation, process, and generate embeddings for a package:

```
$ mix hex.docs.mcp fetch phoenix
```

Fetch documentation for a specific version:

```
$ mix hex.docs.mcp fetch phoenix 1.5.9
```

Use a specific embedding model when fetching:

```
$ mix hex.docs.mcp fetch --model all-minilm phoenix
```

Search in the existing embeddings:

```
$ mix hex.docs.mcp search --query "channels" phoenix
```

Legacy mode (still supported, automatically chooses fetch or search based on presence of --query option):

```
$ mix hex.docs.mcp --query "channels" phoenix  # equivalent to search command
$ mix hex.docs.mcp phoenix                    # equivalent to fetch command
```

This will:

1. Download the package documentation using `mix hex.docs fetch`
2. Convert all HTML files to markdown
3. Save the converted documentation as a single markdown file in `~/.hexdocs_mcp/package/version.md` (or custom path set via HEXDOCS_MCP_PATH)
4. Create semantic text chunks for embedding, stored as JSON files in `~/.hexdocs_mcp/package/chunks/` (or custom path)
5. Generate embeddings using Ollama (unless `--no-embed` is specified), stored in SQLite database at `~/.hexdocs_mcp/hexdocs_mcp.db`
6. Optionally search in the generated embeddings

### MCP Server

The MCP server provides a Model Context Protocol compatible interface to search the embeddings:

```bash
# Navigate to the server directory
cd mcp_server

# Install dependencies
npm install

# Build the project
npm run build

# Start the server (automatically uses ~/.hexdocs_mcp/hexdocs_mcp.db)
npm start
```

The server will be available at http://localhost:4000 and can be used with any MCP client.

For more details see the [MCP Server README](mcp_server/README.md).

## Features

- Downloads package documentation using Hex
- Converts all HTML files to a single consolidated markdown file
- Creates semantic text chunks suitable for vector embedding and retrieval
- Adds metadata to each chunk (package, version, source file)
- Organizes files by package name for easy management
- Preserves file structure information in the markdown
- Handles latest version detection if no version is specified
- Generates embeddings using open source models via Ollama
- Supports semantic search in the generated embeddings
- Flexible model selection for different embedding quality/performance tradeoffs
- MCP-compatible server for easy integration with AI assistants

## Chunk Format

The generated chunks are stored as JSON files with the following structure:

```json
{
  "text": "The chunk content...",
  "metadata": {
    "package": "package_name",
    "version": "version",
    "source_file": "path/to/original/file.html",
    "source_type": "hexdocs",
    "start_byte": 0,
    "end_byte": 100
  }
}
```

These chunks can be directly used for vector embeddings in systems like OpenAI, PostgreSQL pgvector, or other vector databases.