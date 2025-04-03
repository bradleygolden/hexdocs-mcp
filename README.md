# HexDocs MCP

HexDocs MCP is a project that provides semantic search capabilities for Hex package documentation, designed specifically for AI applications. It consists of two main components:

1. An Elixir package that downloads, processes, and generates embeddings from Hex package documentation
2. A TypeScript server implementing the Model Context Protocol (MCP) that provides a searchable interface to the embeddings

## Installation

### Elixir Package

```elixir
def deps do
  [
    {:hexdocs_mcp, "~> 0.1.0", only: :dev}
  ]
end
```

### MCP Client Configuration

The TypeScript MCP server implements the [Model Context Protocol (MCP)](https://modelcontextprotocol.io) and is designed to be used by MCP-compatible clients such as Cursor, Claude Desktop App, Continue, and others. The server provides tools for semantic search of Hex documentation. For a complete list of MCP-compatible clients, see the [MCP Clients documentation](https://modelcontextprotocol.io/clients).

Add this to your client's MCP json config:

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

### Requirements

- [Ollama](https://ollama.ai) - Required for generating embeddings
  - Run `ollama pull nomic-embed-text` to download the recommended embedding model
  - Ensure Ollama is running before using the embedding features
- Elixir 1.16+
- Node.js 22 or later (for the MCP server)

## Configuration

By default, the `mix hex.docs.mcp fetch` command stores all data in `~/.hexdocs_mcp` in the user's home directory. You can change this location by setting the `HEXDOCS_MCP_PATH` environment variable:

```bash
# Example: Set custom storage location
export HEXDOCS_MCP_PATH=/path/to/custom/directory
```

This is also configurable in the MCP configuration for the server:

```json
{
  "mcpServers": {
    "hexdocs-mcp": {
      "command": "npx",
      "args": [
        "-y",
        "hexdocs-mcp"
      ],
      "env": {
        "HEXDOCS_MCP_PATH": "/path/to/custom/directory"
      }
    }
  }
}
```

## Usage

### Elixir Package

If you're using the Elixir package directly (without the MCP server), initialize the SQLite database:

```bash
mix hex.docs.mcp init
```

> **Note:** When using the MCP server, this initialization step is not needed as the database is automatically created when the server starts.

Fetch documentation, process, and generate embeddings for a package:

```bash
mix hex.docs.mcp fetch phoenix
```

Fetch documentation for a specific version:

```bash
mix hex.docs.mcp fetch phoenix 1.5.9
```

Use a specific embedding model when fetching:

```bash
mix hex.docs.mcp fetch --model all-minilm phoenix
```

Search in the existing embeddings:

```bash
mix hex.docs.mcp search --query "channels" phoenix
```

### Pro Tip

When you need documentation for a specific package you don't have already, you can have the AI run the `mix hex.docs.mcp fetch` command for you.

## Acknowledgements

- [hex2text](https://github.com/mjrusso/hex2txt) - For the initial idea and as a reference

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

This project is licensed under MIT - see the [LICENSE](LICENSE) file for details.