# HexMcp

HexMcp is a tool that downloads Hex package documentation, converts it to markdown format, and creates semantic text chunks suitable for embedding in vector databases. It downloads the HTML documentation using the `mix hex.docs` task, converts all HTML files to a single markdown file, and then creates semantically meaningful chunks with metadata.

## Installation

```elixir
def deps do
  [
    {:hex_mcp, "~> 0.1.0"}
  ]
end
```

### Requirements

- [Ollama](https://ollama.ai) - Required for generating embeddings
  - Run `ollama pull nomic-embed-text` to download the recommended embedding model
  - Ensure Ollama is running before using hex_mcp with embedding features

## Usage

Download, process documentation, and generate embeddings for a package (all-in-one):

```
$ mix hex.mcp phoenix
```

Download documentation for a specific version:

```
$ mix hex.mcp phoenix 1.5.9
```

Download and process documentation without generating embeddings:

```
$ mix hex.mcp --no-embed phoenix
```

Use a specific embedding model:

```
$ mix hex.mcp --model all-minilm phoenix
```

Search in the existing embeddings:

```
$ mix hex.mcp --search "channels" phoenix
```

This will:

1. Download the package documentation using `mix hex.docs fetch`
2. Convert all HTML files to markdown
3. Save the converted documentation as a single markdown file in `.hex_mcp/package/version.md`
4. Create semantic text chunks for embedding, stored as JSON files in `.hex_mcp/package/chunks/`
5. Generate embeddings using Ollama (unless `--no-embed` is specified), stored in SQLite database
6. Optionally search in the generated embeddings

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