# HexDocs MCP

HexDocs MCP is a project that provides semantic search capabilities for Hex package documentation, designed specifically for AI applications. It consists of two main components:

1. An Elixir binary that downloads, processes, and generates embeddings from Hex package documentation
2. A TypeScript server implementing the Model Context Protocol (MCP) that calls the Elixir binary to fetch and search documentation

> [!CAUTION]
> **This documentation reflects the current development state on the main branch.**
> For documentation on the latest stable release, please see the [latest release page](https://github.com/bradleygolden/hexdocs-mcp/releases/latest) and the [latest release branch](https://github.com/bradleygolden/hexdocs-mcp/tree/v0.3.0).

## Installation

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
        "hexdocs-mcp@0.3.0"
      ]
    }
  }
}
```

This command will automatically download the elixir binaries to both fetch and search documentation. There's no need to install the elixir binaries separately or even have elixir installed!

#### Smithery

Alternatively, you can use [Smithery](https://smithery.ai/server/@bradleygolden/hexdocs-mcp) to automatically add the MCP server to your client config.

For example, for Cursor, you can use the following command:

```bash
npx -y @smithery/cli@latest install @bradleygolden/hexdocs-mcp --client cursor
```

### Elixir Package

Alternatively, you can add the hexdocs_mcp package to your project if you don't want to use the MCP server.

```elixir
{:hexdocs_mcp, "~> 0.3.0", only: :dev, runtime: false}
```

And if you use floki or any other dependencies that are marked as only available in
another environment, update them to be available in the `:dev` environment as well.

For example floki is commonly used in `:test`:

```elixir
{:floki, ">= 0.30.0", only: :test}
```

But you can update it to be available in the :dev environment:

```elixir
{:floki, ">= 0.30.0", only: [:dev, :test]}
```

### Requirements

- [Ollama](https://ollama.ai) - Required for generating embeddings
  - Run `ollama pull nomic-embed-text` to download the recommended embedding model
  - Ensure Ollama is running before using the embedding features
- Elixir 1.16+
- Node.js 22 or later (for the MCP server)

## Configuration

### Environment Variables

The following environment variables can be used to configure the tool:

| Variable | Description | Default |
|----------|-------------|---------|
| `HEXDOCS_MCP_PATH` | Path where data will be stored | `~/.hexdocs_mcp` |
| `HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL` | Default model to use for embeddings | `nomic-embed-text` |
| `HEXDOCS_MCP_MIX_PROJECT_PATHS` | Comma-separated list of paths to mix.exs files | (none) |

#### Examples:

```bash
# Set custom storage location
export HEXDOCS_MCP_PATH=/path/to/custom/directory

# Use a different default embedding model
export HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL=all-minilm

# Configure common project paths to avoid specifying --project flag each time
export HEXDOCS_MCP_MIX_PROJECT_PATHS="/path/to/project1/mix.exs,/path/to/project2/mix.exs"
```

### MCP Server Configuration

You can also configure environment variables in the MCP configuration for the server:

```json
{
  "mcpServers": {
    "hexdocs-mcp": {
      "command": "...",
      "args": [
        "..."
      ],
      "env": {
        "HEXDOCS_MCP_PATH": "/path/to/custom/directory",
        "HEXDOCS_MCP_DEFAULT_EMBEDDING_MODEL": "all-minilm",
        "HEXDOCS_MCP_MIX_PROJECT_PATHS": "/path/to/project1/mix.exs,/path/to/project2/mix.exs"
      }
    }
  }
}
```

## Usage

### AI Tooling

The MCP server can be used by any MCP-compatible AI tooling. The server will automatically fetch documentation when needed and store it in the configured data directory.

Note that large packages make take time to download and process.

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
mix hex.docs.mcp fetch phoenix --model all-minilm
```

Fetch documentation for a package using the version from your project:

```bash
mix hex.docs.mcp fetch phoenix --project path/to/mix.exs
```

Configure project paths to avoid specifying them every time:

```bash
export HEXDOCS_MCP_MIX_PROJECT_PATHS="/path/to/project1/mix.exs,/path/to/project2/mix.exs"
mix hex.docs.mcp fetch phoenix  # Will use the first path from HEXDOCS_MCP_MIX_PROJECT_PATHS
```

Search in the existing embeddings:

```bash
mix hex.docs.mcp search phoenix --query "channels"
```

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
   mise build
   ```

### Development Tasks

Mise defines several useful development tasks:

- `mise build` - Build both Elixir and TypeScript components
- `mise test` - Run all tests
- `mise mcp_inspect` - Start the MCP inspector for testing the server
- `mise start_mcp_server` - Start the MCP server (primarily for debugging)

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
mix deps --check-unused
mix deps.unlock --all
mix deps.get
mix test

# Instead of mise run mcp_inspect
MCP_INSPECTOR=true npx @modelcontextprotocol/inspector node dist/index.js
```

## AI Assistant Integration

This project includes custom instructions for AI assistants to help optimize your workflow when working with Hex documentation.

### Example Custom Instructions

You can find sample custom instructions in the repository:
- [Cursor rules](.cursor/rules/hexdocs-mcp.mdc) - Custom rules for Cursor editor
- [GitHub Copilot](.github/copilot/instructions.md) - Custom instructions for GitHub Copilot

### Suggested Content

```
When working with Elixir projects that use Hex packages:

## HexDocs MCP Workflow

1. Use `search` to find relevant documentation
2. Use `fetch` to fetch documentation for a package
```

## Release Guidelines

When preparing a new release, please follow these guidelines to ensure consistency:

### Version Management

1. **SemVer Compliance**: Follow [Semantic Versioning](https://semver.org/) strictly:
   - MAJOR: incompatible API changes
   - MINOR: backward-compatible functionality
   - PATCH: backward-compatible bug fixes

2. **Version Synchronization**:
   - Hex package version (in `mix.exs`) and npm package version (in `package.json`) MUST be identical
   - Update both files when changing the version

### Code Style

1. **Formatting and Comments**:
   - Follow the Elixir formatter rules defined in .formatter.exs
   - Do not add comments to code unless strictly necessary for context
   - Self-documenting code with clear function names is preferred
   - Use module and function documentation (@moduledoc and @doc) instead of inline comments

### Changelog Management

1. **Update CHANGELOG.md**:
   - Document all changes under the appropriate heading (Added, Changed, Fixed, etc.)
   - Include the new version number and date
   - Keep an [Unreleased] section for tracking current changes
   - Follow the [Keep a Changelog](https://keepachangelog.com/) format

2. **Entry Format**:
   - Use present tense, imperative style (e.g., "Add feature" not "Added feature")
   - Include issue/PR numbers where applicable
   - Group related changes

### Release Process

1. **Before Release**:
   - Run `mix test` to ensure all tests pass
   - Run `mix format` to ensure code is properly formatted
   - Verify CHANGELOG.md is updated

2. **Release Commits**:
   - Create a version bump commit that updates:
     - mix.exs
     - package.json
     - CHANGELOG.md (move [Unreleased] to new version)
   - Tag the commit with the version number (v0.1.0 format)

3. **After Release**:
   - Add a new [Unreleased] section to CHANGELOG.md
   - Update version links at the bottom of CHANGELOG.md

These guidelines apply to both human contributors and AI assistants working on this project.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

This project is licensed under MIT - see the [LICENSE](https://github.com/bradleygolden/hexdocs-mcp/blob/main/LICENSE) file for details.