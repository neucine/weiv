import assert from "node:assert/strict";
import { test } from "node:test";
import { selectPackages, run } from "./publish-release-helpers.mjs";

test("publisher accepts the collector's four package layout", () => {
  const outputs = [
    { name: "weivjs-weiv-macos-0.1.3.tgz" },
    { name: "weivjs-0.1.3.tgz" },
    { name: "weivjs-weiv-linux-x64-gnu-0.1.3.tgz" },
    { name: "weivjs-weiv-win32-x64-gnu-0.1.3.tgz" },
  ];
  const selected = selectPackages({ version: "0.1.3", platforms: ["macos", "linux", "windows"], outputs });
  assert.equal(selected.length, 4);
  assert.equal(selected.at(-1).name, "weivjs-0.1.3.tgz");
  assert.throws(() => selectPackages({ version: "0.1.3", platforms: ["macos", "linux", "windows"], outputs: outputs.slice(1) }), /Incomplete/);
});

test("publisher command wrapper handles inherited output", () => {
  assert.equal(run(process.execPath, ["-e", "process.stdout.write('ok')"]), "ok");
  assert.equal(run(process.execPath, ["-e", ""], { stdio: "inherit" }), "");
});
