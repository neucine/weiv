import { dirname, join } from "node:path";

// Windows npm is a .cmd launcher, which execFileSync cannot start directly.
// Run its JavaScript entry point with the same Node binary instead.
export function npmCommand(command, args) {
  if (command !== "npm" || process.platform !== "win32") return [command, args];
  return [process.execPath, [join(dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js"), ...args]];
}
