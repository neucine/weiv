import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { execFileSync } from "node:child_process";

const repoRoot = process.cwd();
const tmp = mkdtempSync(join(tmpdir(), "weiv-release-check-"));
const tarballs = [];

function run(cmd, args, cwd, env = process.env) {
  execFileSync(cmd, args, { cwd, env, stdio: "inherit" });
}

function pack(dir) {
  const raw = execFileSync("npm", ["pack", "--json", dir], { cwd: repoRoot, encoding: "utf8" });
  const jsonStart = raw.indexOf("[");
  const parsed = JSON.parse(raw.slice(jsonStart));
  const filename = parsed[0]?.filename;
  if (!filename) throw new Error(`Failed to parse pack output for ${dir}`);
  const full = resolve(repoRoot, filename);
  tarballs.push(full);
  return full;
}

function detectPlaceholder(platformTar) {
  const inspectDir = join(tmp, "inspect");
  run("mkdir", ["-p", inspectDir], repoRoot);
  run("tar", ["-xzf", platformTar, "-C", inspectDir], repoRoot);
  const pkgDir = join(inspectDir, "package");
  const candidates = [
    join(pkgDir, "bin", "weiv"),
    join(pkgDir, "bin", "weiv.exe"),
  ];
  for (const file of candidates) {
    let content = null;
    try {
      content = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (content && content.toLowerCase().includes("placeholder")) {
      throw new Error(`Placeholder binary detected in ${platformTar}. Replace with real platform binary before publish.`);
    }
  }
}

try {
  const mainTar = pack("./packages/weiv");
  const platformTars = [
    pack("./packages/weiv-darwin-arm64"),
    pack("./packages/weiv-darwin-x64"),
    pack("./packages/weiv-linux-x64-gnu"),
    pack("./packages/weiv-linux-arm64-gnu"),
    pack("./packages/weiv-win32-x64-msvc"),
  ];

  for (const t of platformTars) detectPlaceholder(t);

  const app = join(tmp, "app");
  run("mkdir", ["-p", app], repoRoot);
  run("npm", ["init", "-y"], app);
  run("npm", ["install", "--omit=optional", mainTar], app);
  run("node", ["--input-type=module", "-e", "import('weivjs/vite').then(()=>console.log('vite types/export ok'))"], app);
  run("node", ["--input-type=module", "-e", "import('weivjs/bun').then(()=>console.log('bun types/export ok'))"], app);

  console.log("Release check completed (note: platform binaries must be real non-placeholder artifacts).");
} finally {
  rmSync(tmp, { recursive: true, force: true });
  for (const tar of tarballs) rmSync(tar, { force: true });
}
