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

1. Clone the repository
2. Add this to your client's MCP json config:

```json
{
  "mcpServers": {
    "hexdocs-mcp": {
      "command": "node",
      "args": [
        "/path/to/hexdocs-mcp/dist/index.js"
      ]
    }
  }
}
```

I'm working a way to make this easier to configure, but for now, you can use the above. ☺️

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
      "command": "...",
      "args": [
        "..."
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

The SQLite database for vector storage and retrieval is created automatically when needed.

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

## Development

This project uses [mise](https://mise.jdx.dev/) (formerly rtx) to manage development tools and tasks. Mise provides consistent tool versions and task automation across the project.

### Setting Up Development Environment

1. Install mise (if you don't have it already):
   ```bash
   # macOS with Homebrew
   brew install mise
   
   # Using the installer script
   curl https://mise.run | sh
   ```

2. Clone the repository and setup the development environment:
   ```bash
   git clone https://github.com/bradleygolden/hexdocs-mcp.git
   cd hexdocs-mcp
   mise install # Installs the right versions of Elixir and Node.js
   ```

3. Setup dependencies:
   ```bash
   mise run setup_elixir
   mise run setup_ts
   ```

### Development Tasks

Mise defines several useful development tasks:

- `mise run build` - Build both Elixir and TypeScript components
- `mise run test` - Run all tests
- `mise run mcp_inspect` - Start the MCP inspector for testing the server
- `mise run start_mcp_server` - Start the MCP server (primarily for debugging)

### Without Mise

If you prefer not to use mise, you'll need:

- Elixir 1.18.x
- Node.js 22.x

Then, you can run these commands directly:

```bash
# Instead of mise run setup_elixir
mix setup

# Instead of mise run setup_ts
npm install

# Instead of mise run build
mix compile --no-optional-deps --warnings-as-errors
npm run build

# Instead of mise run test
mix test
mix format --check-formatted

# Instead of mise run mcp_inspect
MCP_INSPECTOR=true npx @modelcontextprotocol/inspector node dist/index.js
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

This project is licensed under MIT - see the [LICENSE](LICENSE) file for details.