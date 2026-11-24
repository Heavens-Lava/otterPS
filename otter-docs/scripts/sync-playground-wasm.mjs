#!/usr/bin/env node
/**
 * otter-docs/scripts/sync-playground-wasm.mjs
 *
 * Syncs (optional --from <dir>) and/or verifies the Otter Playground WebAssembly
 * bundle under otter-docs/static/playground/ against playground-manifest.json
 * SHA-256 checksums so the site never builds with missing or corrupted WASM assets.
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultTarget = path.resolve(__dirname, '../static/playground');

const args = process.argv.slice(2);
let fromDir = null;
let targetDir = defaultTarget;
for (let i = 0; i < args.length; i++) {
    if (args[i] === '--from' && args[i + 1]) {
        fromDir = path.resolve(args[i + 1]);
        i++;
    } else if (args[i] === '--target' && args[i + 1]) {
        targetDir = path.resolve(args[i + 1]);
        i++;
    }
}

if (fromDir) {
    if (!fs.existsSync(path.join(fromDir, 'playground-manifest.json'))) {
        throw new Error(`Source WASM bundle missing playground-manifest.json: ${fromDir}`);
    }
    fs.rmSync(targetDir, { recursive: true, force: true });
    fs.cpSync(fromDir, targetDir, { recursive: true });
    console.log(`Synced playground WASM bundle from ${fromDir} -> ${targetDir}`);
}

const manifestPath = path.join(targetDir, 'playground-manifest.json');
if (!fs.existsSync(manifestPath)) {
    throw new Error(`Playground WASM manifest missing at ${manifestPath}. Run sync-playground-wasm.mjs --from <otter-net/artifacts/playground-wasm> first.`);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
    throw new Error('playground-manifest.json contains no files');
}

for (const entry of manifest.files) {
    const full = path.join(targetDir, entry.path);
    if (!fs.existsSync(full)) {
        throw new Error(`Missing playground WASM file: ${entry.path}`);
    }
    const buf = fs.readFileSync(full);
    const actualSha = crypto.createHash('sha256').update(buf).digest('hex');
    if (actualSha !== entry.sha256) {
        throw new Error(`SHA-256 mismatch for ${entry.path}: expected ${entry.sha256}, got ${actualSha}`);
    }
}

const actualTreeSha = crypto
    .createHash('sha256')
    .update(manifest.files.map((f) => `${f.path}:${f.sha256}`).join('\n'))
    .digest('hex');
if (actualTreeSha !== manifest.bundleTreeSha256) {
    throw new Error(`Bundle tree SHA-256 mismatch: expected ${manifest.bundleTreeSha256}, got ${actualTreeSha}`);
}

console.log(
    `Verified playground WASM bundle (${manifest.files.length} files, ` +
    `${(manifest.totalRawBytes / 1048576).toFixed(2)} MB raw, ` +
    `${(manifest.totalGzipBytes / 1048576).toFixed(2)} MB gzip, ` +
    `sha256 ${manifest.bundleTreeSha256.slice(0, 12)}...)`
);
