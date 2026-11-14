#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const root = process.cwd();
const run = (command, args) => execFileSync(command, args, { cwd: root, encoding: "utf8" }).trim();
const commit = process.env.BUILDKITE_COMMIT;
if (process.env.BUILDKITE_BRANCH !== "main" || !/^[a-f0-9]{40}$/.test(commit ?? ""))
  throw Error("Release detection requires a main build commit");
if (run("git", ["rev-parse", "HEAD"]) !== commit) throw Error("Checkout differs from Buildkite commit");

const pulls = JSON.parse(run("gh", ["api", `repos/neucine/weiv/commits/${commit}/pulls`]));
const releases = pulls.filter(pr =>
  pr.merged_at && pr.merge_commit_sha === commit && pr.base?.ref === "main" &&
  /^release\/v\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$/.test(pr.head?.ref ?? ""),
);
if (releases.length === 0) {
  console.log("No merged release PR at this commit; ordinary checks only.");
  process.exit(0);
}
if (releases.length !== 1) throw Error("Expected exactly one merged release PR");
const release = releases[0];
const version = release.head.ref.slice("release/v".length);
const packageVersion = JSON.parse(readFileSync("packages/weiv/package.json", "utf8")).version;
if (packageVersion !== version) throw Error(`Merged release PR is ${version}, but package version is ${packageVersion}`);
run("buildkite-agent", ["meta-data", "set", "release_version", version]);
run("buildkite-agent", ["meta-data", "set", "release_pr", String(release.number)]);
execFileSync("buildkite-agent", ["pipeline", "upload", ".buildkite/merged-release.yml"], { cwd: root, stdio: "inherit" });
console.log(`Added Weiv ${version} release checks for merged PR #${release.number} at ${commit}`);
