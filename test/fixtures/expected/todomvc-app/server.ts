const host = Bun.env.HOST ?? "0.0.0.0";
const port = Number(Bun.env.PORT ?? 3000);

const server = Bun.serve({
  hostname: host,
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
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
