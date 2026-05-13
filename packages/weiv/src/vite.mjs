import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolveWeivBinaryPath } from "./platform.mjs";

function compileWeiv(id) {
  const bin = resolveWeivBinaryPath();
  const compiled = execFileSync(bin, ["compile", "emit", "js", id], {
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
    enforce: "pre",
    resolveId(id) {
      if (id === "weiv:observable" || id === "weiv:router") {
        return `\0${id}`;
      }
      return null;
    },
    load(id) {
      if (id === "\0weiv:observable") {
        return `export * from ${JSON.stringify(observableRuntimePath)};`;
      }
      if (id === "\0weiv:router") {
        return `export * from ${JSON.stringify(routerRuntimePath)};`;
      }
      return null;
    },
    transform(_code, id) {
      if (!id.endsWith(".weiv")) return null;
      const code = compileWeiv(id);
      return { code, map: null };
    }
  };
}
