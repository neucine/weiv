import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

class FakeNode {
  parentNode: FakeElement | FakeDocumentFragment | null = null;

  get nextSibling(): FakeNode | null {
    const parent = this.parentNode;
    if (!parent) return null;
    const index = parent.childNodes.indexOf(this);
    if (index === -1) return null;
    return parent.childNodes[index + 1] ?? null;
  }

  get isConnected(): boolean {
    let current: FakeNode | null = this;
    while (current) {
      if (current instanceof FakeDocument) return true;
      current = current.parentNode;
    }
    return false;
  }
}

class FakeTextNode extends FakeNode {
  constructor(public data: string) {
    super();
  }

  get textContent(): string {
    return this.data;
  }
}

class FakeCommentNode extends FakeNode {
  constructor(public data: string) {
    super();
  }

  get textContent(): string {
    return "";
  }
}

class FakeDocumentFragment extends FakeNode {
  childNodes: FakeNode[] = [];

  append(node: FakeNode) {
    appendChild(this, node);
  }

  insertBefore(node: FakeNode, reference: FakeNode | null) {
    insertBeforeNode(this, node, reference);
  }

  removeChild(node: FakeNode) {
    removeChildNode(this, node);
  }

  get textContent(): string {
    return this.childNodes.map((child) => getTextContent(child)).join("");
  }
}

class FakeElement extends FakeNode {
  childNodes: FakeNode[] = [];
  attributes = new Map<string, string>();
  listeners = new Map<string, Array<(event: any) => void>>();
  replaceChildrenCalls = 0;
  value = "";
  checked = false;
  disabled = false;
  selected = false;
  id = "";
  className = "";
  type = "";

  constructor(public tagName: string) {
    super();
  }

  append(node: FakeNode) {
    appendChild(this, node);
  }

  insertBefore(node: FakeNode, reference: FakeNode | null) {
    insertBeforeNode(this, node, reference);
  }

  removeChild(node: FakeNode) {
    removeChildNode(this, node);
  }

  replaceChildren(...nodes: FakeNode[]) {
    this.replaceChildrenCalls += 1;
    this.childNodes = [];
    for (const node of nodes) {
      this.append(node);
    }
  }

  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
    if (name === "id") this.id = value;
    if (name === "class") this.className = value;
    if (name === "value") this.value = value;
    if (name === "type") this.type = value;
  }

  removeAttribute(name: string) {
    this.attributes.delete(name);
    if (name === "id") this.id = "";
    if (name === "class") this.className = "";
    if (name === "value") this.value = "";
  }

  hasAttribute(name: string): boolean {
    return this.attributes.has(name);
  }

  addEventListener(name: string, handler: (event: any) => void) {
    const handlers = this.listeners.get(name) ?? [];
    handlers.push(handler);
    this.listeners.set(name, handlers);
  }

  dispatchEvent(event: any) {
    const handlers = this.listeners.get(event.type) ?? [];
    event.target = event.target ?? this;
    for (const handler of handlers) {
      handler(event);
    }
  }

  focus() {}
  select() {}

  get textContent(): string {
    return this.childNodes.map((child) => getTextContent(child)).join("");
  }
}

class FakeDocument extends FakeNode {
  body: FakeElement;

  constructor() {
    super();
    this.body = new FakeElement("body");
    this.body.parentNode = this;
  }

  createElement(tagName: string) {
    return new FakeElement(tagName);
  }

  createTextNode(data: string) {
    return new FakeTextNode(data);
  }

  createComment(data: string) {
    return new FakeCommentNode(data);
  }

  createDocumentFragment() {
    return new FakeDocumentFragment();
  }

  getElementById(id: string): FakeElement | null {
    return findElement(this.body, (element) => element.id === id);
  }
}

function adoptNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  node.parentNode = parent;
}

function appendChild(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  if (node instanceof FakeDocumentFragment) {
    for (const child of [...node.childNodes]) {
      adoptNode(parent, child);
      parent.childNodes.push(child);
    }
    node.childNodes = [];
    return;
  }
  adoptNode(parent, node);
  parent.childNodes.push(node);
}

function insertBeforeNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode, reference: FakeNode | null) {
  if (reference === null) {
    appendChild(parent, node);
    return;
  }
  const index = parent.childNodes.indexOf(reference);
  if (index === -1) {
    throw new Error("reference node is not a child of parent");
  }
  if (node instanceof FakeDocumentFragment) {
    for (const child of [...node.childNodes]) {
      adoptNode(parent, child);
    }
    parent.childNodes.splice(index, 0, ...node.childNodes);
    node.childNodes = [];
    return;
  }
  adoptNode(parent, node);
  parent.childNodes.splice(index, 0, node);
}

function removeChildNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  const index = parent.childNodes.indexOf(node);
  if (index === -1) {
    throw new Error("node is not a child of parent");
  }
  parent.childNodes.splice(index, 1);
  node.parentNode = null;
}

function getTextContent(node: FakeNode): string {
  if (node instanceof FakeTextNode) return node.textContent;
  if (node instanceof FakeCommentNode) return node.textContent;
  if (node instanceof FakeElement) return node.textContent;
  if (node instanceof FakeDocumentFragment) return node.textContent;
  return "";
}

function findElement(node: FakeNode, predicate: (element: FakeElement) => boolean): FakeElement | null {
  if (node instanceof FakeElement && predicate(node)) {
    return node;
  }

  const children =
    node instanceof FakeElement ? node.childNodes :
    node instanceof FakeDocumentFragment ? node.childNodes :
    node instanceof FakeDocument ? node.body.childNodes :
    [];

  for (const child of children) {
    const found = findElement(child, predicate);
    if (found) return found;
  }

  return null;
}

function findElements(node: FakeNode, predicate: (element: FakeElement) => boolean, out: FakeElement[] = []): FakeElement[] {
  if (node instanceof FakeElement && predicate(node)) {
    out.push(node);
  }

  const children =
    node instanceof FakeElement ? node.childNodes :
    node instanceof FakeDocumentFragment ? node.childNodes :
    node instanceof FakeDocument ? node.body.childNodes :
    [];

  for (const child of children) {
    findElements(child, predicate, out);
  }

  return out;
}

function byClass(name: string) {
  return (element: FakeElement) => element.className.split(/\s+/).includes(name);
}

function byTag(name: string) {
  return (element: FakeElement) => element.tagName === name;
}

function byTagAndClass(tag: string, className: string) {
  return (element: FakeElement) => element.tagName === tag && byClass(className)(element);
}

function click(element: FakeElement) {
  element.dispatchEvent({ type: "click", target: element });
}

function change(element: FakeElement) {
  element.dispatchEvent({ type: "change", target: element });
}

function dblclick(element: FakeElement) {
  element.dispatchEvent({ type: "dblclick", target: element });
}

function keydown(element: FakeElement, key: string) {
  element.dispatchEvent({ type: "keydown", key, target: element });
}

function emitCommand(args: string[]): string {
  const proc = Bun.spawnSync({
    cmd: ["zig", "build", "run", "--", ...args],
    stdout: "pipe",
    stderr: "pipe",
    cwd: "/Users/chao.yang/Private/weiv",
  });

  if (proc.exitCode !== 0) {
    throw new Error(`command failed: ${args.join(" ")}\n${new TextDecoder().decode(proc.stderr)}`);
  }

  return new TextDecoder().decode(proc.stdout);
}

function emitRenderModule(componentPath: string): string {
  return emitCommand(["emit-render-js", componentPath]);
}

function emitRuntimeModule(): string {
  return emitCommand(["emit-runtime-js"]);
}

function emitAppBundle(rootPath: string, outDir: string): void {
  emitCommand(["emit-app", rootPath, outDir]);
}

async function loadModules(files: Record<string, string>) {
  const dir = mkdtempSync(join(tmpdir(), "weiv-render-"));
  for (const [name, source] of Object.entries(files)) {
    writeFileSync(join(dir, name), source, "utf8");
  }

  try {
    const modules: Record<string, any> = {};
    for (const name of Object.keys(files)) {
      if (!name.endsWith(".mjs") || name === "weiv-runtime.mjs") continue;
      const file = join(dir, name);
      modules[name] = await import(`${pathToFileURL(file).href}?t=${Date.now()}`);
    }
    return modules;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

async function importModule(file: string) {
  return import(`${pathToFileURL(file).href}?t=${Date.now()}`);
}

function assertEqual(actual: string, expected: string, label: string) {
  if (actual !== expected) {
    throw new Error(
      `${label} mismatch\nExpected:\n${expected}\n\nActual:\n${actual}\n`
    );
  }
}

function scopeAttr(scopeId: string): string {
  return ` data-weiv-scope="${scopeId}"`;
}

async function main() {
  const modules = await loadModules({
    "weiv-runtime.mjs": emitRuntimeModule(),
    "BasicCounter.mjs": emitRenderModule("examples/basic-counter.weiv"),
    "TodoItem.mjs": emitRenderModule("examples/classic-todo/TodoItem.weiv"),
    "TodoList.mjs": emitRenderModule("examples/classic-todo/TodoList.weiv"),
  });

  const basicCounterModule = modules["BasicCounter.mjs"];
  const todoItemModule = modules["TodoItem.mjs"];
  const todoListModule = modules["TodoList.mjs"];

  if (!basicCounterModule.css.includes(`[data-weiv-scope="${basicCounterModule.scopeId}"] .counter-card`)) {
    throw new Error("BasicCounter CSS scope mismatch");
  }
  if (!todoItemModule.css.includes(`[data-weiv-scope="${todoItemModule.scopeId}"] .todo-item`)) {
    throw new Error("TodoItem CSS scope mismatch");
  }
  if (!todoListModule.css.includes(`[data-weiv-scope="${todoListModule.scopeId}"] .todo-list`)) {
    throw new Error("TodoList CSS scope mismatch");
  }

  const basicCounterHtml = basicCounterModule.renderToString({
    title: "Counter",
    initialCount: 2,
  });
  assertEqual(
    basicCounterHtml,
    `<section${scopeAttr(basicCounterModule.scopeId)} class="counter-card"><h2${scopeAttr(basicCounterModule.scopeId)}>Counter</h2><p${scopeAttr(basicCounterModule.scopeId)}>Current count: 2</p><p${scopeAttr(basicCounterModule.scopeId)}>Doubled: 4</p><button${scopeAttr(basicCounterModule.scopeId)}>\n      Increment\n    </button></section>`,
    "BasicCounter render"
  );

  const todoItemHtml = todoItemModule.renderToString({
    item: { id: "a", title: "Write tests", completed: false },
  });
  assertEqual(
    todoItemHtml,
    `<article${scopeAttr(todoItemModule.scopeId)} class="todo-item"><label${scopeAttr(todoItemModule.scopeId)} class="todo-item__label"><input${scopeAttr(todoItemModule.scopeId)} type="checkbox"></input><span${scopeAttr(todoItemModule.scopeId)} class="todo-item__copy"><strong${scopeAttr(todoItemModule.scopeId)}>Write tests</strong><em${scopeAttr(todoItemModule.scopeId)}>In progress</em></span></label></article>`,
    "TodoItem render"
  );

  const emptyListHtml = todoListModule.renderToString({
    items: [],
    showCompleted: false,
  });
  assertEqual(
    emptyListHtml,
    `<section${scopeAttr(todoListModule.scopeId)} class="todo-list"><div${scopeAttr(todoListModule.scopeId)} class="todo-list__empty"><p${scopeAttr(todoListModule.scopeId)} class="todo-list__empty-title">Nothing in this lane yet</p><span${scopeAttr(todoListModule.scopeId)} class="todo-list__empty-copy">Active work will land here.</span></div></section>`,
    "TodoList empty render"
  );

  const populatedListHtml = todoListModule.renderToString(
    {
      items: [{ id: "1", title: "Bind template identifiers", completed: false }],
      showCompleted: false,
    },
    {
      TodoItem: todoItemModule,
    }
  );
  assertEqual(
    populatedListHtml,
    `<section${scopeAttr(todoListModule.scopeId)} class="todo-list"><ul${scopeAttr(todoListModule.scopeId)} class="todo-list__items"><li${scopeAttr(todoListModule.scopeId)}><article${scopeAttr(todoItemModule.scopeId)} class="todo-item"><label${scopeAttr(todoItemModule.scopeId)} class="todo-item__label"><input${scopeAttr(todoItemModule.scopeId)} type="checkbox"></input><span${scopeAttr(todoItemModule.scopeId)} class="todo-item__copy"><strong${scopeAttr(todoItemModule.scopeId)}>Bind template identifiers</strong><em${scopeAttr(todoItemModule.scopeId)}>In progress</em></span></label></article></li></ul></section>`,
    "TodoList populated render"
  );

  const bundleDir = mkdtempSync(join(tmpdir(), "weiv-app-bundle-"));
  try {
    emitAppBundle("examples/classic-todo/App.weiv", bundleDir);
    const indexHtml = readFileSync(join(bundleDir, "index.html"), "utf8");
    const browserEntry = readFileSync(join(bundleDir, "main.mjs"), "utf8");
    const propsModule = readFileSync(join(bundleDir, "props.mjs"), "utf8");
    const packageJson = readFileSync(join(bundleDir, "package.json"), "utf8");
    const devServer = readFileSync(join(bundleDir, "server.ts"), "utf8");
    if (!indexHtml.includes('<script type="module" src="./main.mjs"></script>')) {
      throw new Error("Bundled index.html missing browser module entry");
    }
    if (!browserEntry.includes('import { props as previewProps } from "./props.mjs";') ||
        !browserEntry.includes("const props = globalThis.__WEIV_PROPS__ ?? previewProps;") ||
        !browserEntry.includes("AppBundle.mount(target, props);")) {
      throw new Error("Bundled main.mjs missing browser render bootstrap");
    }
    if (!propsModule.includes('export const props = { title: "Preview" };')) {
      throw new Error("Bundled props.mjs missing preview props");
    }
    if (!packageJson.includes('"dev": "bun --hot server.ts"') || !packageJson.includes('"start": "bun server.ts"')) {
      throw new Error("Bundled package.json missing Bun preview scripts");
    }
    if (!devServer.includes("const server = Bun.serve({") || !devServer.includes('pathname === "/" ? "/index.html"')) {
      throw new Error("Bundled server.ts missing static Bun server bootstrap");
    }
    const bundleModule = await importModule(join(bundleDir, "bundle.mjs"));
    const bundledStyles = readFileSync(join(bundleDir, "styles.css"), "utf8");
    if (!bundledStyles.includes(".todo-app") || !bundledStyles.includes(".todo-list") || !bundledStyles.includes(".todo-item")) {
      throw new Error("Bundled styles missing expected selectors");
    }

    const rootScope = bundleModule.root.scopeId;
    const listScope = bundleModule.components.TodoList.scopeId;
    const itemScope = bundleModule.components.TodoItem.scopeId;
    const bundledHtml = bundleModule.renderToString({ title: "Classic Todos" });
    assertEqual(
      bundledHtml,
      `<main${scopeAttr(rootScope)} class="todo-app"><div${scopeAttr(rootScope)} class="todo-app__shell"><header${scopeAttr(rootScope)} class="todo-app__hero"><p${scopeAttr(rootScope)} class="todo-app__eyebrow">Verification Example</p><div${scopeAttr(rootScope)} class="todo-app__headline"><h1${scopeAttr(rootScope)}>Classic Todos</h1><p${scopeAttr(rootScope)} class="todo-app__lede">Client runtime, nested components, scoped styles, and TS-backed helpers in one polished example.</p></div><div${scopeAttr(rootScope)} class="todo-app__summary"><strong${scopeAttr(rootScope)}>2 active tasks</strong><span${scopeAttr(rootScope)}>Viewing active tasks</span></div></header><section${scopeAttr(rootScope)} class="todo-app__panel"><div${scopeAttr(rootScope)} class="todo-app__panel-header"><div${scopeAttr(rootScope)}><p${scopeAttr(rootScope)} class="todo-app__panel-label">Inbox</p><h2${scopeAttr(rootScope)}>Product Todo Board</h2></div><button${scopeAttr(rootScope)} class="todo-app__filter">Show completed</button></div><section${scopeAttr(listScope)} class="todo-list"><ul${scopeAttr(listScope)} class="todo-list__items"><li${scopeAttr(listScope)}><article${scopeAttr(itemScope)} class="todo-item"><label${scopeAttr(itemScope)} class="todo-item__label"><input${scopeAttr(itemScope)} type="checkbox"></input><span${scopeAttr(itemScope)} class="todo-item__copy"><strong${scopeAttr(itemScope)}>Polish the flagship todo verification app</strong><em${scopeAttr(itemScope)}>In progress</em></span></label></article></li><li${scopeAttr(listScope)}><article${scopeAttr(itemScope)} class="todo-item"><label${scopeAttr(itemScope)} class="todo-item__label"><input${scopeAttr(itemScope)} type="checkbox"></input><span${scopeAttr(itemScope)} class="todo-item__copy"><strong${scopeAttr(itemScope)}>Tighten DOM event semantics</strong><em${scopeAttr(itemScope)}>In progress</em></span></label></article></li></ul></section></section></div></main>`,
      "Classic todo bundled render"
    );
  } finally {
    rmSync(bundleDir, { recursive: true, force: true });
  }

  const counterBundleDir = mkdtempSync(join(tmpdir(), "weiv-counter-bundle-"));
  try {
    emitAppBundle("examples/basic-counter.weiv", counterBundleDir);
    const counterProps = readFileSync(join(counterBundleDir, "props.mjs"), "utf8");
    if (!counterProps.includes('title: "Preview"') || !counterProps.includes("initialCount: 0")) {
      throw new Error("BasicCounter bundled props.mjs missing inferred preview props");
    }
  } finally {
    rmSync(counterBundleDir, { recursive: true, force: true });
  }

  const importedHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-helper-bundle-"));
  try {
    emitAppBundle("examples/imported-helper/App.weiv", importedHelperBundleDir);
    const helperModule = readFileSync(join(importedHelperBundleDir, "format.js"), "utf8");
    const punctuationModule = readFileSync(join(importedHelperBundleDir, "punctuation.js"), "utf8");
    const helperAppModule = readFileSync(join(importedHelperBundleDir, "App.mjs"), "utf8");
    const helperProps = readFileSync(join(importedHelperBundleDir, "props.mjs"), "utf8");
    if (!helperModule.includes("export function formatTitle")) {
      throw new Error("Imported helper bundle missing copied format.js");
    }
    if (!helperModule.includes('import { suffix } from "./punctuation.js";')) {
      throw new Error("Imported helper bundle missing transitive helper import");
    }
    if (!punctuationModule.includes('export const suffix = "!";')) {
      throw new Error("Imported helper bundle missing copied punctuation.js");
    }
    if (!helperAppModule.includes('import { formatTitle } from "./format.js";')) {
      throw new Error("Imported helper bundle missing preserved runtime import");
    }
    if (!helperProps.includes('title: "Preview"') || !helperProps.includes("count: 0")) {
      throw new Error("Imported helper bundle missing inferred preview props");
    }

    const importedHelperBundle = await importModule(join(importedHelperBundleDir, "bundle.mjs"));
    const importedHelperHtml = importedHelperBundle.renderToString({
      title: "Codex",
      count: 7,
    });
    const importedScope = importedHelperBundle.root.scopeId;
    assertEqual(
      importedHelperHtml,
      `<section${scopeAttr(importedScope)} class="imported-helper"><h1${scopeAttr(importedScope)}>Hello, Codex!</h1><p${scopeAttr(importedScope)}>7</p></section>`,
      "Imported helper bundled render"
    );
  } finally {
    rmSync(importedHelperBundleDir, { recursive: true, force: true });
  }

  const importedTsHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-ts-helper-bundle-"));
  try {
    emitAppBundle("examples/imported-ts-helper/App.weiv", importedTsHelperBundleDir);
    const tsHelperModule = readFileSync(join(importedTsHelperBundleDir, "format.js"), "utf8");
    const tsPunctuationModule = readFileSync(join(importedTsHelperBundleDir, "punctuation.js"), "utf8");
    const tsHelperAppModule = readFileSync(join(importedTsHelperBundleDir, "App.mjs"), "utf8");
    const tsHelperProps = readFileSync(join(importedTsHelperBundleDir, "props.mjs"), "utf8");
    if (!tsHelperModule.includes('import { suffix } from "./punctuation.js";')) {
      throw new Error("Imported TS helper bundle missing rewritten transitive helper import");
    }
    if (!tsPunctuationModule.includes('export const suffix = "!";')) {
      throw new Error("Imported TS helper bundle missing transpiled punctuation.js");
    }
    if (!tsHelperAppModule.includes('import { formatTitle } from "./format.js";')) {
      throw new Error("Imported TS helper bundle missing rewritten app import");
    }
    if (!tsHelperProps.includes('title: "Preview"') || !tsHelperProps.includes("count: 0")) {
      throw new Error("Imported TS helper bundle missing inferred preview props");
    }

    const importedTsHelperBundle = await importModule(join(importedTsHelperBundleDir, "bundle.mjs"));
    const importedTsHelperHtml = importedTsHelperBundle.renderToString({
      title: "Codex",
      count: 11,
    });
    const importedTsScope = importedTsHelperBundle.root.scopeId;
    assertEqual(
      importedTsHelperHtml,
      `<section${scopeAttr(importedTsScope)} class="imported-ts-helper"><h1${scopeAttr(importedTsScope)}>TS hello, Codex!</h1><p${scopeAttr(importedTsScope)}>11</p></section>`,
      "Imported TS helper bundled render"
    );
  } finally {
    rmSync(importedTsHelperBundleDir, { recursive: true, force: true });
  }

  const todomvcBundleDir = mkdtempSync(join(tmpdir(), "weiv-todomvc-bundle-"));
  try {
    emitAppBundle("examples/todomvc/App.weiv", todomvcBundleDir);
    const todomvcBundle = await importModule(join(todomvcBundleDir, "bundle.mjs"));
    const todomvcStyles = readFileSync(join(todomvcBundleDir, "styles.css"), "utf8");
    if (!todomvcStyles.includes(".todo-header") ||
        !todomvcStyles.includes(".todo-footer") ||
        !todomvcStyles.includes(".toggle-all") ||
        !todomvcStyles.includes(".newtodo")) {
      throw new Error("TodoMVC bundle missing expected selectors");
    }

    const rootScope = todomvcBundle.root.scopeId;
    const headerScope = todomvcBundle.components.TodoHeader.scopeId;
    const listScope = todomvcBundle.components.TodoList.scopeId;
    const itemScope = todomvcBundle.components.TodoItem.scopeId;
    const footerScope = todomvcBundle.components.TodoFooter.scopeId;
    const inputScope = todomvcBundle.components.TodoTextInput.scopeId;
    const todomvcHtml = todomvcBundle.renderToString({ title: "todos" });
    assertEqual(
      todomvcHtml,
      `<main${scopeAttr(rootScope)} class="todomvc-page"><section${scopeAttr(rootScope)} class="todoapp"><header${scopeAttr(headerScope)} class="todo-header"><h1${scopeAttr(headerScope)}>todos</h1><input${scopeAttr(inputScope)} autofocus type="text" class="newtodo" placeholder="What needs to be done?" value=""></input></header><section${scopeAttr(rootScope)} class="main"><input${scopeAttr(rootScope)} class="toggle-all" type="checkbox"></input><ul${scopeAttr(listScope)} class="todo-list"><li${scopeAttr(itemScope)} class="completed"><div${scopeAttr(itemScope)} class="view"><input${scopeAttr(itemScope)} class="toggle" type="checkbox" checked></input><label${scopeAttr(itemScope)}>Port TodoMVC into the verification suite</label><button${scopeAttr(itemScope)} class="destroy"></button></div></li><li${scopeAttr(itemScope)}><div${scopeAttr(itemScope)} class="view"><input${scopeAttr(itemScope)} class="toggle" type="checkbox"></input><label${scopeAttr(itemScope)}>Verify root-owned state updates across nested components</label><button${scopeAttr(itemScope)} class="destroy"></button></div></li><li${scopeAttr(itemScope)}><div${scopeAttr(itemScope)} class="view"><input${scopeAttr(itemScope)} class="toggle" type="checkbox"></input><label${scopeAttr(itemScope)}>Exercise edit, filter, and clear-completed flows</label><button${scopeAttr(itemScope)} class="destroy"></button></div></li><li${scopeAttr(itemScope)}><div${scopeAttr(itemScope)} class="view"><input${scopeAttr(itemScope)} class="toggle" type="checkbox"></input><label${scopeAttr(itemScope)}>Keep scoped CSS realistic under a larger tree</label><button${scopeAttr(itemScope)} class="destroy"></button></div></li><li${scopeAttr(itemScope)} class="completed"><div${scopeAttr(itemScope)} class="view"><input${scopeAttr(itemScope)} class="toggle" type="checkbox" checked></input><label${scopeAttr(itemScope)}>Expose the polished preview on the LAN server</label><button${scopeAttr(itemScope)} class="destroy"></button></div></li></ul></section><footer${scopeAttr(footerScope)} class="todo-footer"><span${scopeAttr(footerScope)} class="todo-count"><strong${scopeAttr(footerScope)}>3</strong><span${scopeAttr(footerScope)} class="todo-count__suffix"> items left</span></span><ul${scopeAttr(footerScope)} class="filters"><li${scopeAttr(footerScope)}><button${scopeAttr(footerScope)} class="selected">All</button></li><li${scopeAttr(footerScope)}><button${scopeAttr(footerScope)} class="">Active</button></li><li${scopeAttr(footerScope)}><button${scopeAttr(footerScope)} class="">Completed</button></li></ul><button${scopeAttr(footerScope)} class="clear-completed">Clear completed</button></footer></section></main>`,
      "TodoMVC bundled render"
    );

    const fakeDocument = new FakeDocument();
    const appTarget = fakeDocument.createElement("div");
    appTarget.setAttribute("id", "app");
    fakeDocument.body.append(appTarget);
    (globalThis as any).document = fakeDocument;

    todomvcBundle.mount(appTarget, { title: "todos" });
    if (appTarget.replaceChildrenCalls !== 1) {
      throw new Error(`TodoMVC mount expected 1 root replaceChildren call, found ${appTarget.replaceChildrenCalls}`);
    }

    let labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (labels.length !== 5) {
      throw new Error(`TodoMVC mount expected 5 labels, found ${labels.length}`);
    }

    const newTodoInput = findElement(fakeDocument.body, byClass("newtodo"));
    if (!newTodoInput) throw new Error("TodoMVC mount missing newtodo input");
    newTodoInput.value = "Verify browser interaction checks";
    keydown(newTodoInput, "Enter");

    labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (labels[0] !== "Verify browser interaction checks") {
      throw new Error("TodoMVC create flow did not prepend the new todo");
    }

    let filterButtons = findElements(fakeDocument.body, byTag("button")).filter((element) =>
      ["All", "Active", "Completed"].includes(element.textContent.trim())
    );
    let activeButton = filterButtons.find((element) => element.textContent.trim() === "Active");
    if (!activeButton) throw new Error("TodoMVC active filter button missing");
    click(activeButton);

    labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (labels.some((text) => text.includes("Port TodoMVC into the verification suite"))) {
      throw new Error("TodoMVC active filter still shows completed items");
    }

    const activeLabels = findElements(fakeDocument.body, byTag("label"));
    const editLabel = activeLabels.find((element) => element.textContent.includes("Exercise edit, filter, and clear-completed flows"));
    if (!editLabel) throw new Error("TodoMVC edit target label missing");
    const replaceChildrenCallsBeforeEdit = appTarget.replaceChildrenCalls;
    dblclick(editLabel);
    if (appTarget.replaceChildrenCalls !== replaceChildrenCallsBeforeEdit) {
      throw new Error("TodoMVC edit-mode entry rerendered the app root instead of the item boundary");
    }

    const editInput = findElement(fakeDocument.body, byClass("edit"));
    if (!editInput) throw new Error("TodoMVC edit flow did not open edit input");
    editInput.value = "Exercise edit, filter, clear-completed, and dev flows";
    keydown(editInput, "Enter");

    labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (!labels.includes("Exercise edit, filter, clear-completed, and dev flows")) {
      throw new Error("TodoMVC edit flow did not persist the updated text");
    }

    const activeToggles = findElements(fakeDocument.body, byClass("toggle"));
    const createdToggle = activeToggles[0];
    if (!createdToggle) throw new Error("TodoMVC toggle flow missing active toggle");
    createdToggle.checked = true;
    change(createdToggle);

    labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (labels.includes("Verify browser interaction checks")) {
      throw new Error("TodoMVC active filter did not drop toggled completed item");
    }

    filterButtons = findElements(fakeDocument.body, byTag("button")).filter((element) =>
      ["All", "Active", "Completed"].includes(element.textContent.trim())
    );
    const allButton = filterButtons.find((element) => element.textContent.trim() === "All");
    if (!allButton) throw new Error("TodoMVC all filter button missing");
    click(allButton);

    const clearCompletedButton = findElements(fakeDocument.body, byTagAndClass("button", "clear-completed"))[0];
    if (!clearCompletedButton) throw new Error("TodoMVC clear completed button missing");
    click(clearCompletedButton);

    labels = findElements(fakeDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (labels.includes("Port TodoMVC into the verification suite") ||
        labels.includes("Expose the polished preview on the LAN server") ||
        labels.includes("Verify browser interaction checks")) {
      throw new Error("TodoMVC clear completed flow did not remove completed items");
    }
  } finally {
    rmSync(todomvcBundleDir, { recursive: true, force: true });
  }

  process.stdout.write("render checks passed\n");
}

await main();
