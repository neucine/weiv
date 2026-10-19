import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolveWeivBinaryPath } from "./platform.mjs";

const WEIV_STYLE_SUFFIX = "?weiv-style.css";

function compileWeiv(id, format) {
  const bin = resolveWeivBinaryPath();
  return execFileSync(bin, ["compile", "emit", format, id], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
}

function analyzeWeiv(id) {
  const bin = resolveWeivBinaryPath();
  const output = execFileSync(bin, ["analyze", "component", id, "--json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  });
  return JSON.parse(output).diagnostics ?? [];
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
  const observableRuntimePath = fileURLToPath(new URL("./runtime/observable.js", import.meta.url));
  const routerRuntimePath = fileURLToPath(new URL("./runtime/router.js", import.meta.url));

  return {
    name: "weiv",
    enforce: "pre",
    resolveId(id) {
      if (id === "weiv:observable" || id === "weiv:router") {
        return `\0${id}`;
      }
      if (id.endsWith(WEIV_STYLE_SUFFIX)) {
        return id;
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
      if (id.endsWith(WEIV_STYLE_SUFFIX)) {
        const componentPath = id.slice(0, -WEIV_STYLE_SUFFIX.length);
        this.addWatchFile(componentPath);
        return compileWeiv(componentPath, "css");
      }
      return null;
    },
    transform(_code, id) {
      if (!id.endsWith(".weiv")) return null;
      for (const diagnostic of analyzeWeiv(id)) {
        if (diagnostic.severity !== "warning") continue;
        const warning = {
          message: `[${diagnostic.code}] ${diagnostic.message}`,
          id
        };
        if (diagnostic.location) {
          warning.loc = {
            file: id,
            line: diagnostic.location.line,
            column: Math.max(0, diagnostic.location.column - 1)
          };
        }
        this.warn(warning);
      }
      const compiled = compileWeiv(id, "js");
      const styleRequest = `${id}${WEIV_STYLE_SUFFIX}`;
      const code = `${rewriteRuntimeImports(compiled)}\nimport ${JSON.stringify(styleRequest)};\n`;
      return { code, map: null };
    }
  };
}
