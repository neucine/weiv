import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const compiler = process.env.CYNA || "cyna";
const manifest = resolve(
  repoRoot,
  process.platform === "linux"
    ? "cyna.release.linux.toml"
    : process.platform === "win32"
      ? "cyna.release.windows.toml"
      : "cyna.release.toml",
);
const output = resolve(repoRoot, "cyna-out", "bin", process.platform === "win32" ? "weiv.exe" : "weiv");
const env = { ...process.env };
const platformName = {
  "darwin-arm64": "weiv-darwin-arm64",
  "linux-x64": "weiv-linux-x64-gnu",
  "win32-x64": "weiv-win32-x64-gnu",
}[`${process.platform}-${process.arch}`];
const platformPackage = platformName
  ? resolve(repoRoot, "packages", platformName, "bin", process.platform === "win32" ? "weiv.exe" : "weiv")
  : null;

if (process.platform === "darwin" && !env.SDKROOT) {
  env.SDKROOT = execFileSync("xcrun", ["--show-sdk-path"], { encoding: "utf8" }).trim();
}

mkdirSync(dirname(output), { recursive: true });
const rustTarget = process.platform === "win32" ? "x86_64-pc-windows-gnu" : null;
if (rustTarget) {
  env.CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER ??= "C:\\msys64\\mingw64\\bin\\gcc.exe";
}
execFileSync(
  "cargo",
  [
    "build",
    "--release",
    "--locked",
    ...(rustTarget ? ["--target", rustTarget] : []),
    "--manifest-path",
    resolve(repoRoot, "libs", "parser-backend", "Cargo.toml"),
  ],
  {
    cwd: repoRoot,
    env,
    stdio: "inherit",
  },
);
if (rustTarget) {
  const linkDir = resolve(repoRoot, "libs", "parser-backend", "target", rustTarget, "release");
  const linkInputs = [
    [
      env.WEIV_WINDOWS_SYNCHRONIZATION_LIB ||
        "C:\\Program Files (x86)\\Windows Kits\\10\\Lib\\10.0.26100.0\\um\\x64\\Synchronization.lib",
      "Synchronization.lib",
    ],
    [
      env.WEIV_WINDOWS_GCC_EH || "C:\\msys64\\mingw64\\lib\\gcc\\x86_64-w64-mingw32\\16.2.0\\libgcc_eh.a",
      "libgcc_eh.a",
    ],
  ];
  for (const [source, name] of linkInputs) {
    if (!existsSync(source)) throw new Error(`Missing Windows link input: ${source}`);
    copyFileSync(source, resolve(linkDir, name));
  }
}
execFileSync(compiler, ["build", manifest, "--output", output, "--verbose", "--timings"], {
  cwd: repoRoot,
  env,
  stdio: "inherit",
});
if (platformPackage) {
  mkdirSync(dirname(platformPackage), { recursive: true });
  copyFileSync(output, platformPackage);
}

console.log(`Built Cyna release binary at ${output}`);
if (platformPackage) console.log(`Updated platform package binary at ${platformPackage}`);
