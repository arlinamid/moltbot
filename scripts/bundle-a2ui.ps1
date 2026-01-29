# bundle-a2ui.ps1 - Windows PowerShell version of bundle-a2ui.sh
$ErrorActionPreference = "Stop"

function Write-ErrorMessage {
    Write-Error "A2UI bundling failed. Re-run with: pnpm canvas:a2ui:bundle"
    Write-Error "If this persists, verify pnpm deps and try again."
}

trap { Write-ErrorMessage; break }

$ROOT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HASH_FILE = Join-Path $ROOT_DIR "src\canvas-host\a2ui\.bundle.hash"
$OUTPUT_FILE = Join-Path $ROOT_DIR "src\canvas-host\a2ui\a2ui.bundle.js"
$A2UI_RENDERER_DIR = Join-Path $ROOT_DIR "vendor\a2ui\renderers\lit"
$A2UI_APP_DIR = Join-Path $ROOT_DIR "apps\shared\MoltbotKit\Tools\CanvasA2UI"

# Docker builds exclude vendor/apps via .dockerignore.
# In that environment we must keep the prebuilt bundle.
if (-not (Test-Path $A2UI_RENDERER_DIR -PathType Container) -or -not (Test-Path $A2UI_APP_DIR -PathType Container)) {
    Write-Host "A2UI sources missing; keeping prebuilt bundle."
    exit 0
}

$INPUT_PATHS = @(
    (Join-Path $ROOT_DIR "package.json"),
    (Join-Path $ROOT_DIR "pnpm-lock.yaml"),
    $A2UI_RENDERER_DIR,
    $A2UI_APP_DIR
)

function Compute-Hash {
    $hashScript = @'
import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";

const rootDir = process.env.ROOT_DIR ?? process.cwd();
const inputs = process.argv.slice(2);
const files = [];

async function walk(entryPath) {
  const st = await fs.stat(entryPath);
  if (st.isDirectory()) {
    const entries = await fs.readdir(entryPath);
    for (const entry of entries) {
      await walk(path.join(entryPath, entry));
    }
    return;
  }
  files.push(entryPath);
}

for (const input of inputs) {
  await walk(input);
}

function normalize(p) {
  return p.split(path.sep).join("/");
}

files.sort((a, b) => normalize(a).localeCompare(normalize(b)));

const hash = createHash("sha256");
for (const filePath of files) {
  const rel = normalize(path.relative(rootDir, filePath));
  hash.update(rel);
  hash.update("\0");
  hash.update(await fs.readFile(filePath));
  hash.update("\0");
}

process.stdout.write(hash.digest("hex"));
'@

    $env:ROOT_DIR = $ROOT_DIR
    $tempFile = [System.IO.Path]::GetTempFileName() + ".mjs"
    Set-Content -Path $tempFile -Value $hashScript -Encoding UTF8
    try {
        $result = & node $tempFile @INPUT_PATHS
        return $result
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item Env:ROOT_DIR -ErrorAction SilentlyContinue
    }
}

$current_hash = Compute-Hash

if (Test-Path $HASH_FILE) {
    $previous_hash = Get-Content $HASH_FILE -Raw
    $previous_hash = $previous_hash.Trim()
    if ($previous_hash -eq $current_hash -and (Test-Path $OUTPUT_FILE)) {
        Write-Host "A2UI bundle up to date; skipping."
        exit 0
    }
}

$tsconfigPath = Join-Path $A2UI_RENDERER_DIR "tsconfig.json"
$rolldownConfigPath = Join-Path $A2UI_APP_DIR "rolldown.config.mjs"

pnpm -s exec tsc -p $tsconfigPath
if ($LASTEXITCODE -ne 0) { throw "tsc failed" }

rolldown -c $rolldownConfigPath
if ($LASTEXITCODE -ne 0) { throw "rolldown failed" }

Set-Content -Path $HASH_FILE -Value $current_hash -NoNewline -Encoding UTF8
Write-Host "A2UI bundle built successfully."
