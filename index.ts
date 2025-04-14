#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import * as path from "path";
import * as fs from "fs/promises";
import { existsSync } from "fs";
import { execFile } from "child_process";
import { promisify } from "util";
import { fileURLToPath } from "url";
import { createHash } from 'crypto';
import { pipeline } from 'stream';
import { createWriteStream } from 'fs';

const execFileAsync = promisify(execFile);
const pipelineAsync = promisify(pipeline);

// Get package version
async function getPackageVersion(): Promise<string> {
    const packageJson = JSON.parse(
        await fs.readFile(
            new URL('../package.json', import.meta.url),
            'utf-8'
        )
    );
    return packageJson.version;
}

// Get binary metadata
async function getBinaryMetadata(binaryPath: string): Promise<{ app_version: string } | null> {
    try {
        const { stdout } = await execFileAsync(binaryPath, ['maintenance', 'meta']);
        return JSON.parse(stdout);
    } catch (error) {
        console.error(`Warning: Failed to get binary metadata: ${error instanceof Error ? error.message : 'Unknown error'}`);
        return null;
    }
}

// Binary management
const GITHUB_REPO = 'bradleygolden/hexdocs-mcp';

// Platform-specific binary names
const BINARY_NAMES = {
    win32: {
        x64: 'hexdocs_mcp_windows.exe',
        arm64: 'hexdocs_mcp_windows.exe', // Currently same as x64
    },
    darwin: {
        x64: 'hexdocs_mcp_macos',
        arm64: 'hexdocs_mcp_macos_arm',
    },
    linux: {
        x64: 'hexdocs_mcp_linux',
        arm64: 'hexdocs_mcp_linux', // Currently same as x64
    }
} as const;

async function getBinaryName(): Promise<string> {
    const platform = process.platform;
    const arch = process.arch;

    const platformBinaries = BINARY_NAMES[platform as keyof typeof BINARY_NAMES];
    if (!platformBinaries) {
        throw new Error(`Unsupported platform: ${platform}`);
    }

    const binaryName = platformBinaries[arch as keyof typeof platformBinaries];
    if (!binaryName) {
        throw new Error(`Unsupported architecture ${arch} for platform ${platform}`);
    }

    return binaryName;
}

async function getBinaryPath(): Promise<string> {
    const __dirname = path.dirname(fileURLToPath(import.meta.url));
    const binaryPath = path.join(__dirname, '..', 'bin', await getBinaryName());

    if (existsSync(binaryPath)) {
        const metadata = await getBinaryMetadata(binaryPath);
        const packageVersion = await getPackageVersion();

        if (!metadata || metadata.app_version !== packageVersion) {
            console.error(`Binary version mismatch (got ${metadata?.app_version}, expected ${packageVersion})`);
            await downloadBinary(binaryPath);
        }
    } else {
        await downloadBinary(binaryPath);
    }

    return binaryPath;
}

// Get release base URL (either GitHub or local test release)
async function getReleaseBaseUrl(version: string): Promise<string> {
    if (process.env.NODE_ENV === 'development' && process.env.HEXDOCS_MCP_TEST_RELEASE_PATH) {
        return `file://${process.env.HEXDOCS_MCP_TEST_RELEASE_PATH}`;
    }
    return `https://github.com/${GITHUB_REPO}/releases/download/${version}`;
}

async function downloadBinary(targetPath: string): Promise<void> {
    try {
        // Create bin directory if it doesn't exist
        await fs.mkdir(path.dirname(targetPath), { recursive: true });

        // Try to use local binary first
        if (await copyLocalBinary(targetPath)) {
            return;
        }

        // Fall back to downloading from GitHub or using test release
        const version = `v${await getPackageVersion()}`;
        const binaryName = await getBinaryName();
        const baseUrl = await getReleaseBaseUrl(version);
        const binDir = path.dirname(targetPath);

        // Define paths for verification files
        const checksumsPath = path.join(binDir, 'SHA256SUMS');
        const sigPath = path.join(binDir, 'SHA256SUMS.asc');
        const keyPath = path.join(binDir, 'SIGNING_KEY.asc');

        // Download verification files
        console.error('Downloading verification files...');
        await downloadFile(`${baseUrl}/SHA256SUMS`, checksumsPath);

        // Check if we can do GPG verification
        const gpgAvailable = await isGPGAvailable();
        if (gpgAvailable) {
            await downloadFile(`${baseUrl}/SHA256SUMS.asc`, sigPath);
            await downloadFile(`${baseUrl}/SIGNING_KEY.asc`, keyPath);

            // Verify GPG signature
            console.error('Verifying GPG signature...');
            const isSignatureValid = await verifyGPGSignature(checksumsPath, sigPath, keyPath);
            if (!isSignatureValid) {
                throw new Error('GPG signature verification failed');
            }
            console.error('GPG signature verification passed');
        }

        // Download binary
        const downloadUrl = `${baseUrl}/${binaryName}`;
        console.error(`Downloading binary from ${downloadUrl}`);
        await downloadFile(downloadUrl, targetPath);

        // Verify checksum
        console.error('Verifying checksum...');
        const isChecksumValid = await verifyChecksum(targetPath, checksumsPath);
        if (!isChecksumValid) {
            throw new Error('Checksum verification failed');
        }
        console.error('Checksum verification passed');

        // Make binary executable
        await makeExecutable(targetPath);

        // Clean up verification files
        await fs.rm(checksumsPath, { force: true });
        if (gpgAvailable) {
            await fs.rm(sigPath, { force: true });
            await fs.rm(keyPath, { force: true });
        }

        console.error(`Successfully downloaded and verified binary version ${version} to ${targetPath}`);
    } catch (error) {
        const version = await getPackageVersion();
        throw new Error(`Failed to download binary version v${version}: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}

// Platform-specific executable permissions
async function makeExecutable(filePath: string): Promise<void> {
    if (process.platform !== 'win32') {
        try {
            await fs.chmod(filePath, 0o755);
        } catch (error) {
            console.error('Warning: Failed to set executable permissions:', error instanceof Error ? error.message : 'Unknown error');
        }
    }
}

// Update copyLocalBinary to use platform-safe paths
async function copyLocalBinary(targetPath: string): Promise<boolean> {
    try {
        const __dirname = path.dirname(fileURLToPath(import.meta.url));
        const binaryName = await getBinaryName();
        const localBinaryPath = path.join(__dirname, '..', 'burrito_out', binaryName);

        if (existsSync(localBinaryPath)) {
            console.error(`Found local binary at ${localBinaryPath}`);
            await fs.copyFile(localBinaryPath, targetPath);
            await makeExecutable(targetPath);
            console.error(`Successfully copied local binary to ${targetPath}`);
            return true;
        }
        return false;
    } catch (error) {
        console.error(`Warning: Failed to copy local binary: ${error instanceof Error ? error.message : 'Unknown error'}`);
        return false;
    }
}

// Update file operations to be platform-safe
async function downloadFile(url: string, targetPath: string): Promise<void> {
    if (url.startsWith('file://')) {
        // For local testing, copy the file instead of downloading
        const sourcePath = url.replace('file://', '');
        await fs.copyFile(path.join(sourcePath, path.basename(targetPath)), targetPath);
        return;
    }

    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download: ${response.statusText} (HTTP ${response.status})`);
    }
    const fileStream = createWriteStream(targetPath);
    await pipelineAsync(response.body as any, fileStream);
}

// Check if GPG is available
async function isGPGAvailable(): Promise<boolean> {
    try {
        await execFileAsync('gpg', ['--version']);
        return true;
    } catch (error) {
        console.error('GPG is not available on this system. Falling back to checksum verification only.');
        return false;
    }
}

async function verifyGPGSignature(checksumPath: string, signaturePath: string, publicKeyPath: string): Promise<boolean> {
    try {
        // Import the public key
        await execFileAsync('gpg', ['--import', publicKeyPath]);

        // Verify the signature
        const { stdout, stderr } = await execFileAsync('gpg', [
            '--verify',
            signaturePath,
            checksumPath
        ]);

        // Log verification details
        console.error('GPG verification output:', stdout || stderr);

        return true;
    } catch (error) {
        console.error('GPG verification failed:', error instanceof Error ? error.message : 'Unknown error');
        return false;
    }
}

async function verifyChecksum(filePath: string, checksumFile: string): Promise<boolean> {
    try {
        // Read and parse the checksums file
        const checksums = await fs.readFile(checksumFile, 'utf-8');
        const binaryName = path.basename(filePath);

        // Find the matching checksum line
        const checksumLine = checksums
            .split('\n')
            .find(line => line.includes(binaryName));

        if (!checksumLine) {
            throw new Error(`No checksum found for ${binaryName}`);
        }

        // Extract the expected hash (first part of the line)
        const expectedHash = checksumLine.split(/\s+/)[0];

        // Calculate file hash
        const hash = createHash('sha256');
        const fileBuffer = await fs.readFile(filePath);
        hash.update(fileBuffer);
        const calculatedHash = hash.digest('hex');

        return calculatedHash.toLowerCase() === expectedHash.toLowerCase();
    } catch (error) {
        console.error('Checksum verification error:', error instanceof Error ? error.message : 'Unknown error');
        return false;
    }
}

// Command handlers
async function handleSearch(args: {
    query: string;
    packageName: string;
    version?: string;
    limit?: number;
}) {
    const binaryPath = await getBinaryPath();
    const cliArgs = ['search', args.packageName];

    if (args.version) {
        cliArgs.push(args.version);
    }

    cliArgs.push('--query', args.query);

    if (args.limit) {
        cliArgs.push('--limit', args.limit.toString());
    }

    try {
        const { stdout } = await execFileAsync(binaryPath, cliArgs);
        return { content: [{ type: "text" as const, text: stdout }] };
    } catch (error) {
        throw new Error(`Search failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}

async function handleFetch(args: {
    packageName: string;
    version?: string;
    force?: boolean;
}) {
    const binaryPath = await getBinaryPath();
    const cliArgs = ['fetch', args.packageName];

    if (args.version) {
        cliArgs.push(args.version);
    }

    if (args.force) {
        cliArgs.push('--force');
    }

    try {
        const { stdout } = await execFileAsync(binaryPath, cliArgs);
        return { content: [{ type: "text" as const, text: stdout }] };
    } catch (error) {
        throw new Error(`Fetch failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}

const args = process.argv.slice(2);
const isCheckBinary = args.includes('--check-binary');

async function main() {
    if (isCheckBinary) {
        console.error("Checking binary...");
        const binaryPath = await getBinaryPath();
        console.error(`Binary available at: ${binaryPath}`);
        console.error("Binary check complete.");
        return;
    }

    console.error("Initializing MCP server...");
    const server = new McpServer({
        name: "HexdocsMCP",
        version: "0.2.0",
        description: "MCP server for searching Elixir Hex package documentation using embeddings"
    });

    // Register tools
    server.tool(
        "search",
        {
            query: z.string().describe("The semantic search query to find relevant documentation (can be natural language, not just keywords)"),
            packageName: z.string().describe("The Hex package name to search within (must be a package that has been fetched)"),
            version: z.string().optional().describe("Optional specific package version to search within, defaults to latest fetched version"),
            limit: z.number().optional().default(5).describe("Maximum number of results to return (default: 5, increase for more comprehensive results)")
        },
        handleSearch
    );

    server.tool(
        "fetch",
        {
            packageName: z.string().describe("The Hex package name to fetch (required)"),
            version: z.string().optional().describe("Optional package version, defaults to latest"),
            force: z.boolean().optional().default(false).describe("Force re-fetch even if embeddings already exist")
        },
        handleFetch
    );

    // Start the server with reconnection handling
    console.error("Starting server...");
    const transport = new StdioServerTransport();

    async function connectWithRetry(transport: StdioServerTransport) {
        try {
            await server.connect(transport);
            console.error("Connected to transport");
        } catch (error) {
            console.error(`Connection error: ${error instanceof Error ? error.message : 'Unknown error'}, retrying in 5s...`);
            setTimeout(() => connectWithRetry(transport), 5000);
        }
    }

    connectWithRetry(transport);
}

main();