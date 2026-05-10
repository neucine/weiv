import { test } from "bun:test";
import {
  emitDirectBrowserModule,
  installJsdom,
  loadModules,
} from "./support";

function clickButton(target: Element, win: any) {
  const button = target.querySelector("button");
  if (!button) throw new Error("Missing button");
  button.dispatchEvent(new win.Event("click", { bubbles: true }));
}

test("basic counter works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "BasicCounter.mjs": emitDirectBrowserModule("test/examples/basic/basic-counter.weiv"),
  });

  const mod = modules["BasicCounter.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, { title: "Counter", initialCount: 2 });

  if (!target.textContent?.includes("Current count: 2")) {
    throw new Error(`Initial text mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Doubled: 4")) {
    throw new Error(`Initial doubled mismatch: ${target.textContent}`);
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Current count: 3")) {
    throw new Error(`After click text mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Doubled: 6")) {
    throw new Error(`After click doubled mismatch: ${target.textContent}`);
  }

  for (let i = 0; i < 7; i++) clickButton(target, win);

  const button = target.querySelector("button") as any;
  if (!button?.disabled) {
    throw new Error("Button should be disabled after reaching limit");
  }
});

test("conditional toggle works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "ConditionalToggle.mjs": emitDirectBrowserModule("test/examples/basic/conditional-toggle.weiv"),
  });

  const mod = modules["ConditionalToggle.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, {});

  if (!target.textContent?.includes("Panel is closed")) {
    throw new Error(`Initial branch mismatch: ${target.textContent}`);
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Panel is open")) {
    throw new Error(`After toggle mismatch: ${target.textContent}`);
  }
  if (target.textContent?.includes("Panel is closed")) {
    throw new Error("Old branch still visible after toggle");
  }
});

test("todo list works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "TodoList.mjs": emitDirectBrowserModule("test/examples/basic/todo-list.weiv"),
  });

  const mod = modules["TodoList.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, { title: "Tasks" });

  if (!target.textContent?.includes("Showing pending tasks")) {
    throw new Error(`Initial filter mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Implement template binder")) {
    throw new Error(`Missing pending item: ${target.textContent}`);
  }
  if (target.textContent?.includes("Write parser fixtures")) {
    throw new Error("Completed item visible in pending mode");
  }

  clickButton(target, win);

  if (!target.textContent?.includes("Showing completed tasks")) {
    throw new Error(`After toggle filter mismatch: ${target.textContent}`);
  }
  if (!target.textContent?.includes("Write parser fixtures")) {
    throw new Error(`Missing completed item: ${target.textContent}`);
  }
});

test("timer callback works with jsdom real DOM", async () => {
  const modules = await loadModules({
    "TimerCallback.mjs": emitDirectBrowserModule("test/examples/basic/timer-callback.weiv"),
  });

  const mod = modules["TimerCallback.mjs"];
  const { document: doc, window: win } = installJsdom();
  const target = doc.createElement("div");
  doc.body.appendChild(target);

  mod.mount(target, {});

  if (!target.textContent?.includes("0")) {
    throw new Error(`Initial content mismatch: ${target.textContent}`);
  }

  clickButton(target, win);
  await new Promise((resolve) => setTimeout(resolve, 10));

  if (!target.textContent?.includes("1")) {
    throw new Error(`After timer callback mismatch: ${target.textContent}`);
  }
});
