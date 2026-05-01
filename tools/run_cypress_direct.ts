import { createServer } from "node:net";

const cwd = "/Users/chao.yang/Private/weiv";
const outDir = ".zig-cache/cypress-todomvc-direct";

async function findFreePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("Failed to determine a free port")));
        return;
      }
      const { port } = address;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function waitForServer(url: string, timeoutMs: number): Promise<void> {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {}
    await Bun.sleep(300);
  }
  throw new Error(`Timed out waiting for ${url}`);
}

async function main() {
  const port = String(await findFreePort());
  const baseUrl = `http://127.0.0.1:${port}`;

  const server = Bun.spawn({
    cmd: ["zig", "build", "run", "--", "dev", "examples/todomvc/App.weiv", outDir],
    cwd,
    env: {
      ...process.env,
      PORT: port,
    },
    stdout: "inherit",
    stderr: "inherit",
    stdin: "ignore",
  });

  const stopServer = () => {
    try {
      server.kill("SIGTERM");
    } catch {}
  };

  process.on("SIGINT", stopServer);
  process.on("SIGTERM", stopServer);

  try {
    await waitForServer(baseUrl, 60_000);

    const cypress = Bun.spawn({
      cmd: ["bunx", "cypress", "run", "--headless", "--browser", "electron"],
      cwd,
      env: {
        ...process.env,
        CYPRESS_BASE_URL: baseUrl,
      },
      stdout: "inherit",
      stderr: "inherit",
      stdin: "ignore",
    });

    const exitCode = await cypress.exited;
    if (exitCode !== 0) {
      throw new Error(`Cypress exited with code ${exitCode}`);
    }
  } finally {
    stopServer();
    await server.exited;
  }
}

await main();
