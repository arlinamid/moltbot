#!/usr/bin/env node
/**
 * Cross-platform environment variable setter for npm scripts.
 * Usage: node scripts/cross-env.mjs VAR1=value1 VAR2=value2 -- command args...
 */
import { spawn } from "node:child_process";
import process from "node:process";

const args = process.argv.slice(2);
const separatorIndex = args.indexOf("--");

if (separatorIndex === -1) {
    console.error("Usage: cross-env VAR=value -- command [args...]");
    process.exit(1);
}

const envPairs = args.slice(0, separatorIndex);
const command = args.slice(separatorIndex + 1);

if (command.length === 0) {
    console.error("No command specified after --");
    process.exit(1);
}

const env = { ...process.env };

for (const pair of envPairs) {
    const eqIndex = pair.indexOf("=");
    if (eqIndex === -1) {
        console.error(`Invalid environment variable: ${pair}`);
        process.exit(1);
    }
    const key = pair.slice(0, eqIndex);
    const value = pair.slice(eqIndex + 1);
    env[key] = value;
}

const isWindows = process.platform === "win32";
const [cmd, ...cmdArgs] = command;

// On Windows, use cmd.exe to properly handle PATH lookups
const spawnCmd = isWindows ? "cmd.exe" : cmd;
const spawnArgs = isWindows ? ["/d", "/s", "/c", cmd, ...cmdArgs] : cmdArgs;

const child = spawn(spawnCmd, spawnArgs, {
    cwd: process.cwd(),
    env,
    stdio: "inherit",
    shell: !isWindows,
});

child.on("exit", (code, signal) => {
    if (signal) {
        process.exit(1);
    }
    process.exit(code ?? 1);
});
