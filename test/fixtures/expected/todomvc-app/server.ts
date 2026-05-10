const host = Bun.env.HOST ?? "0.0.0.0";
const port = Number(Bun.env.PORT ?? 3000);

const server = Bun.serve({
  hostname: host,
  port,
  async fetch(req) {
    const url = new URL(req.url);
    const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
    const file = Bun.file(new URL(`.${pathname}`, import.meta.url));

    if (!(await file.exists())) {
      return new Response("Not Found", { status: 404 });
    }

    return new Response(file);
  },
});

console.log(`weiv preview server running at http://${host}:${server.port}`);
