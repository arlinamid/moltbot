#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process";
import process from "node:process";

const args = process.argv.slice(2);
const env = { ...process.env };
const cwd = process.cwd();
const compiler = env.CLAWDBOT_TS_COMPILER === "tsc" ? "tsc" : "tsgo";
const projectArgs = ["--project", "tsconfig.json"];
const isWindows = process.platform === "win32";

// On Windows, use shell: true for proper .cmd resolution
const spawnOptions = { cwd, env, stdio: "inherit", shell: isWindows };

const initialBuild = spawnSync("pnpm", ["exec", compiler, ...projectArgs], spawnOptions);

if (initialBuild.status !== 0) {
  process.exit(initialBuild.status ?? 1);
}

const watchArgs =
  compiler === "tsc"
    ? [...projectArgs, "--watch", "--preserveWatchOutput"]
    : [...projectArgs, "--watch"];

const compilerProcess = spawn("pnpm", ["exec", compiler, ...watchArgs], spawnOptions);

const nodeProcess = spawn(process.execPath, ["--watch", "moltbot.mjs", ...args], {
  cwd,
  env,
  stdio: "inherit",
});


let exiting = false;

function cleanup(code = 0) {
  if (exiting) return;
  exiting = true;
  if (isWindows) {
    // Windows: use taskkill for reliable process termination
    try {
      spawnSync("taskkill", ["/pid", String(nodeProcess.pid), "/T", "/F"], { stdio: "ignore" });
    } catch { }
    try {
      spawnSync("taskkill", ["/pid", String(compilerProcess.pid), "/T", "/F"], { stdio: "ignore" });
    } catch { }
  } else {
    nodeProcess.kill("SIGTERM");
    compilerProcess.kill("SIGTERM");
  }
  process.exit(code);
}

process.on("SIGINT", () => cleanup(130));
process.on("SIGTERM", () => cleanup(143));
// Windows: handle Ctrl+C properly
if (isWindows) {
  process.on("SIGHUP", () => cleanup(129));
}

compilerProcess.on("exit", (code) => {
  if (exiting) return;
  cleanup(code ?? 1);
});

nodeProcess.on("exit", (code, signal) => {
  if (signal || exiting) return;
  cleanup(code ?? 1);
});
