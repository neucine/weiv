import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveWeivBinaryPath } from "./platform.mjs";

function compileWeiv(filePath) {
  const bin = resolveWeivBinaryPath();
  const compiled = execFileSync(bin, ["compile", "emit", "js", filePath], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  return rewriteRuntimeImports(compiled);
}

function rewriteRuntimeImports(code) {
  return code.replace(
    /import\s*\{([^}]+)\}\s*from\s*["']@weiv\/runtime["'];?/g,
    (_match, importsChunk) => {
      const rawImports = importsChunk
        .split(",")
        .map((entry) => entry.trim())
        .filter(Boolean);

      const routerImports = [];
      const observableImports = [];

      for (const spec of rawImports) {
        const importedName = spec.split(/\s+as\s+/)[0].trim();
        if (importedName === "createRouter") {
          routerImports.push(spec);
        } else {
          observableImports.push(spec);
        }
      }

      const lines = [];
      if (observableImports.length > 0) {
        lines.push(`import { ${observableImports.join(", ")} } from "weiv:observable";`);
      }
      if (routerImports.length > 0) {
        lines.push(`import { ${routerImports.join(", ")} } from "weiv:router";`);
      }
      return lines.join("\n");
    }
  );
}

export function weiv() {
  const observableRuntimePath = fileURLToPath(new URL("./runtime/observable.ts", import.meta.url));
  const routerRuntimePath = fileURLToPath(new URL("./runtime/router.ts", import.meta.url));

  return {
    name: "weiv",
    setup(build) {
      build.onResolve({ filter: /^weiv:(observable|router)$/ }, (args) => ({
        path: args.path,
        namespace: "weiv-virtual",
      }));

      build.onLoad({ filter: /^weiv:observable$/, namespace: "weiv-virtual" }, () => ({
        contents: `export * from ${JSON.stringify(observableRuntimePath)};`,
        loader: "js",
      }));

      build.onLoad({ filter: /^weiv:router$/, namespace: "weiv-virtual" }, () => ({
        contents: `export * from ${JSON.stringify(routerRuntimePath)};`,
        loader: "js",
      }));

      build.onLoad({ filter: /\.weiv$/ }, (args) => {
        const code = compileWeiv(path.resolve(args.path));
        return {
          contents: code,
          loader: "js"
        };
      });
    }
  };
}
