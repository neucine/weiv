import { execFileSync } from "node:child_process";

export function run(cmd, args, options = {}) {
  return execFileSync(cmd, args, { encoding: "utf8", ...options })?.trim() ?? "";
}

export function selectPackages(manifest) {
  const mainName = `weivjs-${manifest.version}.tgz`;
  const main = manifest.outputs.find(item => item.name === mainName);
  const platforms = manifest.outputs.filter(item => item.name !== mainName);
  if (!main || platforms.length !== manifest.platforms.length || manifest.outputs.length !== manifest.platforms.length + 1)
    throw Error("Incomplete release packages");
  return [...platforms, main];
}
