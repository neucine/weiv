import { spawn } from "node:child_process";
import { resolveWeivBinaryPath } from "./platform.mjs";

export function runWeivCli(args) {
  const bin = resolveWeivBinaryPath();
  const child = spawn(bin, args, {
    stdio: "inherit",
    env: process.env
  });

  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 1);
  });
}
