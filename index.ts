#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as path from "path";
import * as os from "os";
import * as fs from "fs";
import BetterSqlite3 from "better-sqlite3";
import { Ollama } from "ollama";
import * as sqliteVec from "sqlite-vec";

// Define types for our database rows
interface PackageRow {
    package: string;
}

interface EmbeddingRow {
    embedding: string;
    text: string;
    package: string;
    version: string;
    source_file: string;
}

interface SearchResult {
    id: number;
    package: string;
    version: string;
    source_file: string;
    text: string;
    score: number;
}

// Get home directory or custom path from environment
const homedir = os.homedir();
const hexdocsPath = process.env.HEXDOCS_MCP_PATH || path.join(homedir, '.hexdocs_mcp');
const defaultDbPath = path.join(hexdocsPath, 'hexdocs_mcp.db');

// Parse command line arguments
const args = process.argv.slice(2);
const dbPath = args[0] || defaultDbPath;

// Ensure the directory exists
if (!fs.existsSync(path.dirname(dbPath))) {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    console.log(`Created directory for database at: ${path.dirname(dbPath)}`);
}

// Create MCP server
const server = new McpServer({
    name: "HexdocsMCP",
    version: "0.1.0"
});

// Initialize database connection with lazy initialization
let db: BetterSqlite3.Database;
try {
    const dbExists = fs.existsSync(dbPath);
    db = new BetterSqlite3(dbPath);
    
    // Initialize the schema if database is new
    if (!dbExists) {
        console.log(`Initializing new database at: ${dbPath}`);
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
} catch (error) {
    console.error(`Error initializing database: ${error instanceof Error ? error.message : 'Unknown error'}`);
    process.exit(1);
}

// Load SQLite vector extension
sqliteVec.load(db);

// Initialize Ollama client
const ollama = new Ollama();

// Helper function to calculate cosine similarity
function cosineSimilarity(a: number[], b: number[]): number {
    let dotProduct = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
        dotProduct += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }
    return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}

// Add resources
server.resource(
    "packages",
    "packages://list",
    async () => {
        const packages = db.prepare("SELECT DISTINCT package FROM embeddings").all() as PackageRow[];
        return {
            contents: [{
                uri: "packages://list",
                text: JSON.stringify(packages.map(p => p.package))
            }]
        };
    }
);

// Add tools
server.tool(
    "vector_search",
    {
        query: z.string(),
        packageName: z.string(),
        version: z.string().optional(),
        limit: z.number().optional().default(5)
    },
    async ({ query, packageName, version, limit }) => {
        try {
            // Get query embedding from Ollama
            const queryEmbedding = await ollama.embeddings({
                model: "nomic-embed-text",
                prompt: query
            });

            // Prepare SQL query to get embeddings and content
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
            const params: any[] = [embeddingBuffer, packageName];

            if (version && version !== "latest") {
                sql += " AND e.version = ?";
                params.push(version);
            }

            sql += " ORDER BY score LIMIT ?";
            params.push(limit);

            // Get all relevant embeddings
            const rows = db.prepare(sql).all(...params) as SearchResult[];

            // Format results for display
            const formattedResults = rows.map(row =>
                `Source: ${row.source_file} (v${row.version})\nRelevance: ${(1 - row.score).toFixed(3)}\n\n${row.text}\n---\n`
            ).join('\n');

            return {
                content: [{
                    type: "text",
                    text: formattedResults || "No relevant results found."
                }]
            };
        } catch (error) {
            console.error('Error during vector search:', error);
            return {
                content: [{
                    type: "text",
                    text: `Error performing search: ${error instanceof Error ? error.message : 'Unknown error'}`
                }],
                isError: true
            };
        }
    }
);

// Start the server
async function main() {
    try {
        const transport = new StdioServerTransport();
        await server.connect(transport);
    } catch (error) {
        console.error('Error starting server:', error);
        process.exit(1);
    }
}

main(); 