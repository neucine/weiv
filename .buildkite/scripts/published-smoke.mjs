#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const manifest = JSON.parse(readFileSync("dist/release/collected/manifest.json", "utf8"));
const version = manifest.version;
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$/.test(version)) throw Error("Invalid release version");
if (manifest.commit !== process.env.BUILDKITE_COMMIT) throw Error("Release commit mismatch");

const consumer = mkdtempSync(join(tmpdir(), "weiv-release-smoke-"));
const run = (program, args) => {
  const result = spawnSync(program, args, {
    cwd: consumer,
    stdio: "inherit",
    shell: process.platform === "win32" && program === "npm",
  });
  if (result.error) throw result.error;
  return result.status === 0;
};
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

try {
  // npm can accept a publish before its registry mirrors serve the new package.
  // Retry the consumer install without repeating the platform build or publish.
  let installed = false;
  for (let attempt = 1; attempt <= 12; attempt++) {
    console.log(`Installing published weivjs@${version} (attempt ${attempt}/12)`);
    installed = run("npm", ["install", "--no-audit", "--no-fund", "--ignore-scripts", `weivjs@${version}`]);
    if (installed) break;
    if (attempt < 12) await delay(10_000);
  }
  if (!installed) throw Error("Published npm install did not become available within two minutes");
  if (!run(process.execPath, [join(consumer, "node_modules/weivjs/bin/weiv.mjs"), "--help"]))
    throw Error("Published Weiv CLI failed");
  if (!run(process.execPath, ["--input-type=module", "-e", "await import('weivjs/vite'); await import('weivjs/bun')"]))
    throw Error("Published adapter imports failed");
} finally {
  rmSync(consumer, { recursive: true, force: true });
}
