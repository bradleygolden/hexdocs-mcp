# HexDocs MCP

HexDocs MCP is a wrapper around the `mix hex.docs` command that adds functionality for generating embeddings from Hex package documentation. These embeddings are specifically designed for use in AI applications, specifically for MCP servers in this use case.

## Components

The project consists of two main components:

1. **Elixir HexDocs Mcp (this project)** - Downloads, processes and embeds Hex package documentation
2. [**HexDocs MCP Server**](https://github.com/bradleygolden/hexdocs-mcp-server) - A TypeScript implementation of the Model Context Protocol (MCP) that provides a searchable interface to the embeddings in an easily installable format via `npx`

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

## Configuration

By default, HexDocs MCP stores all data in `~/.hexdocs_mcp` in the user's home directory. You can change this location by setting the `HEXDOCS_MCP_PATH` environment variable:

```bash
# Example: Set custom storage location
export HEXDOCS_MCP_PATH=/path/to/custom/directory
```

## Usage

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

### Pro Tip

You can use the `hexdocs_mcp_server` library within your AI tooling to programmatically generate commands for adding packages using `mix hex.docs.mcp` so you don't have to manually. For example, an AI might find that you don't have the documentation for a given tool and then recognize it can run `mix hex.docs.mcp fetch ...`.

## Chunk Format

The generated chunks are stored as JSON files with the following structure or similar:

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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

This project is licensed under MIT - see the [LICENSE](LICENSE) file for details.