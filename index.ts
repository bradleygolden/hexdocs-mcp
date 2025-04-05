#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
    CallToolRequestSchema,
    ListToolsRequestSchema,
    ToolSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import * as path from "path";
import * as os from "os";
import * as fs from "fs/promises";
import { existsSync, mkdirSync } from "fs";
import BetterSqlite3 from "better-sqlite3";
import { Ollama } from "ollama";
import * as sqliteVec from "sqlite-vec";
import { zodToJsonSchema } from "zod-to-json-schema";

// Define parameter schemas using zod
const VectorSearchSchema = z.object({
    query: z.string().describe("The search query to find relevant documentation"),
    packageName: z.string().describe("The Hex package name to search within"),
    version: z.string().optional().describe("Optional package version, defaults to latest"),
    limit: z.number().optional().default(5).describe("Maximum number of results to return")
});

// Types
interface SearchResult {
    id: number;
    package: string;
    version: string;
    source_file: string;
    text: string;
    score: number;
}

// Global vars
let db: BetterSqlite3.Database;
let ollama: Ollama;

// Get database path
const getDbPath = () => {
    const homedir = os.homedir();
    const hexdocsPath = process.env.HEXDOCS_MCP_PATH || path.join(homedir, '.hexdocs_mcp');
    const defaultDbPath = path.join(hexdocsPath, 'hexdocs_mcp.db');

    // Parse command line arguments
    const args = process.argv.slice(2);
    const dbPath = args[0] || defaultDbPath;

    return { hexdocsPath, dbPath };
};

// Initialize database
const initializeDatabase = async (dbPath: string) => {
    try {
        // Ensure directory exists
        const dirPath = path.dirname(dbPath);
        if (!existsSync(dirPath)) {
            mkdirSync(dirPath, { recursive: true });
            console.error(`Created directory for database at: ${dirPath}`);
        }

        const dbExists = existsSync(dbPath);
        db = new BetterSqlite3(dbPath);

        // Initialize the schema if database is new
        if (!dbExists) {
            console.error(`Initializing new database at: ${dbPath}`);
            db.exec(`
        CREATE TABLE IF NOT EXISTS embeddings(
          id INTEGER PRIMARY KEY,
          package TEXT NOT NULL,
          version TEXT NOT NULL,
          source_file TEXT NOT NULL,
          source_type TEXT,
          start_byte INTEGER,
          end_byte INTEGER,
          text_snippet TEXT,
          text TEXT NOT NULL,
          embedding BLOB NOT NULL,
          inserted_at TIMESTAMP,
          updated_at TIMESTAMP,
          UNIQUE(package, version, source_file, text_snippet)
        );
        CREATE INDEX IF NOT EXISTS idx_embeddings_package_version ON embeddings(package, version);
      `);
        }

        // Load SQLite vector extension
        sqliteVec.load(db);

        return true;
    } catch (error) {
        console.error(`Error initializing database: ${error instanceof Error ? error.message : 'Unknown error'}`);
        return false;
    }
};

// Vector search tool handler
const vectorSearchHandler = async (params: z.infer<typeof VectorSearchSchema>) => {
    try {
        // Check if db and ollama are initialized
        if (!db) {
            throw new Error("Database not initialized");
        }

        if (!ollama) {
            throw new Error("Ollama client not initialized");
        }

        const { query, packageName, version, limit } = params;

        // Get query embedding from Ollama
        console.error(`Getting embedding for query: "${query}"`);
        const queryEmbedding = await ollama.embeddings({
            model: "nomic-embed-text",
            prompt: query
        });

        if (!queryEmbedding || !queryEmbedding.embedding) {
            throw new Error("Failed to generate embedding for query");
        }

        // Prepare SQL query
        let sql = `
      SELECT 
        e.id,
        e.package,
        e.version,
        e.source_file,
        e.text,
        vec_distance_L2(e.embedding, ?) as score
      FROM embeddings e
      WHERE e.package = ?
    `;

        // Convert embedding to binary format for SQLite
        const embeddingBuffer = Buffer.from(new Float32Array(queryEmbedding.embedding).buffer);
        const sqlParams: any[] = [embeddingBuffer, packageName];

        if (version && version !== "latest") {
            sql += " AND e.version = ?";
            sqlParams.push(version);
        }

        sql += " ORDER BY score LIMIT ?";
        sqlParams.push(limit || 5);

        console.error(`Executing query for package: ${packageName}, version: ${version || 'latest'}, limit: ${limit || 5}`);

        // Get all relevant embeddings
        const rows = db.prepare(sql).all(...sqlParams) as SearchResult[];
        console.error(`Found ${rows.length} results`);

        // Format results
        const results = rows.map(row => ({
            source_file: row.source_file,
            version: row.version,
            relevance: (1 - row.score).toFixed(3),
            text: row.text
        }));

        return {
            results: results || [],
            count: results.length
        };
    } catch (error) {
        console.error(`Error during vector search: ${error instanceof Error ? error.message : 'Unknown error'}`);
        throw new Error(`Search failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
};

// Create MCP server
console.error("Initializing MCP server...");
const server = new Server(
    {
        name: "HexdocsMCP",
        version: "0.1.2",
        description: "MCP server for searching Elixir Hex package documentation using embeddings"
    },
    {
        capabilities: {
            tools: {}, // Indicates support for tools
        }
    }
);


// Set up handler for tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (!request.params) {
        throw new Error("Parameters are required");
    }

    const { name, params = {} } = request.params;

    if (name === "vector_search") {
        try {
            // Check if we have arguments or params
            const args = request.params.arguments || params;
            console.error(`Received vector_search request with args: ${JSON.stringify(args)}`);

            // Parse and validate params
            const parsedParams = VectorSearchSchema.parse(args);
            const result = await vectorSearchHandler(parsedParams);
            return {
                content: [{
                    type: "text",
                    text: JSON.stringify(result)
                }]
            };
        } catch (error) {
            console.error(`Vector search error: ${error instanceof Error ? error.message : 'Unknown error'}`);
            return {
                content: [{
                    type: "text",
                    text: `Failed to perform search: ${error instanceof Error ? error.message : 'Unknown error'}`
                }],
                isError: true
            };
        }
    }

    throw new Error(`Unknown tool: ${name}`);
});

// Set up handler for listing tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
        tools: [
            {
                name: "vector_search",
                description:
                    "Perform semantic search within Elixir Hex package documentation using vector embeddings. " +
                    "This tool uses embeddings generated from package documentation to find semantically " +
                    "relevant content based on your query, not just exact keyword matches. " +
                    "\n\n" +
                    "Usage guidelines:" +
                    "\n- Use specific, focused queries for best results" +
                    "\n- The packageName must be a package that exists in the database" +
                    "\n- If results aren't relevant, try rephrasing your query or using more domain-specific terms" +
                    "\n- For packages not in the database, fetch them with: `mix hex.docs.mcp fetch PACKAGE [VERSION]`" +
                    "\n\n" +
                    "Results include source file, version, relevance score, and the matching text snippet. " +
                    "This tool helps you quickly find relevant documentation without having to browse " +
                    "through the entire package documentation.",
                inputSchema: {
                    type: "object",
                    properties: {
                        query: {
                            type: "string",
                            description: "The semantic search query to find relevant documentation (can be natural language, not just keywords)"
                        },
                        packageName: {
                            type: "string",
                            description: "The Hex package name to search within (must be a package that has been fetched)"
                        },
                        version: {
                            type: "string",
                            description: "Optional specific package version to search within, defaults to latest fetched version"
                        },
                        limit: {
                            type: "number",
                            description: "Maximum number of results to return (default: 5, increase for more comprehensive results)",
                            default: 5
                        }
                    },
                    required: ["query", "packageName"]
                },
                parameters: zodToJsonSchema(VectorSearchSchema)
            }
        ]
    };
});

async function connectWithRetry(transport: StdioServerTransport) {
    try {
        await server.connect(transport);
        console.error("Connected to transport");
    } catch (error) {
        console.error(`Connection error: ${error instanceof Error ? error.message : 'Unknown error'}, retrying in 5s...`);
        setTimeout(connectWithRetry, 5000);
    }
}

// Main function
async function main() {
    // Get paths
    const { dbPath } = getDbPath();

    // Initialize DB
    console.error("Initializing database connection...");
    const dbInitialized = await initializeDatabase(dbPath);
    if (!dbInitialized) {
        process.exit(1);
    }

    // Initialize Ollama client
    console.error("Initializing Ollama client...");
    ollama = new Ollama();

    // Start the server with reconnection handling
    console.error("Starting server...");
    const transport = new StdioServerTransport();

    connectWithRetry(transport);
}

// Run the main function
main().catch(error => {
    console.error(`Unhandled error: ${error instanceof Error ? error.message : 'Unknown error'}`);
    process.exit(1);
});