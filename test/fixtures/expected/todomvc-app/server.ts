const host = Bun.env.HOST ?? "0.0.0.0";
const port = Number(Bun.env.PORT ?? 3000);
const packagePrefix = "/__weiv_packages/";
const packageBundles = new Map<string, Promise<Blob>>();

function bundlePackage(specifier: string) {
  let pending = packageBundles.get(specifier);
  if (!pending) {
    pending = (async () => {
      const entrypoint = Bun.resolveSync(specifier, import.meta.dir);
      const result = await Bun.build({ entrypoints: [entrypoint], target: "browser", format: "esm" });
      if (!result.success || result.outputs.length !== 1) {
        throw new Error(`Failed to bundle package ${specifier}`);
      }
      return result.outputs[0];
    })();
    packageBundles.set(specifier, pending);
  }
  return pending;
}

const server = Bun.serve({
  hostname: host,
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
    if (pathname.startsWith(packagePrefix)) {
      const specifier = decodeURIComponent(pathname.slice(packagePrefix.length));
      if (!specifier || specifier.startsWith(".") || specifier.includes("\\")) {
        return new Response("Invalid package specifier", { status: 400 });
      }
      try {
        return new Response(await bundlePackage(specifier), { headers: { "content-type": "text/javascript; charset=utf-8" } });
      } catch (error) {
        return new Response(String(error), { status: 404 });
      }
    }
    const staticFile = Bun.file(new URL(`.${pathname}`, import.meta.url));

    if (await staticFile.exists()) {
      return new Response(staticFile);
    }

    const fallbackFile = Bun.file(new URL("./index.html", import.meta.url));
    if (await fallbackFile.exists()) {
      return new Response(fallbackFile);
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`weiv preview server running at http://${host}:${server.port}`);
