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
  if (node.parentNode) {
    const currentParent = node.parentNode;
    const currentIndex = currentParent.childNodes.indexOf(node);
    if (currentIndex !== -1) {
      currentParent.childNodes.splice(currentIndex, 1);
    }
  }
  node.parentNode = parent;
}

function appendChild(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  if (node instanceof FakeDocumentFragment) {
    const children = [...node.childNodes];
    node.childNodes = [];
    for (const child of children) {
      adoptNode(parent, child);
      parent.childNodes.push(child);
    }
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
    const children = [...node.childNodes];
    node.childNodes = [];
    for (const child of children) {
      adoptNode(parent, child);
    }
    parent.childNodes.splice(index, 0, ...children);
    return;
  }
  adoptNode(parent, node);
  const nextIndex = parent.childNodes.indexOf(reference);
  if (nextIndex === -1) {
    throw new Error("reference node was detached during insert");
  }
  parent.childNodes.splice(nextIndex, 0, node);
}

function removeChildNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  const index = parent.childNodes.indexOf(node);
  if (index === -1) {
    throw new Error("node is not a child of parent");
  }
  parent.childNodes.splice(index, 1);
  node.parentNode = null;
}

function replaceBetweenNodes(start: FakeNode, end: FakeNode, content: FakeNode) {
  const parent = start.parentNode;
  if (!parent || parent !== end.parentNode) {
    throw new Error("boundary is detached");
  }
  let current = start.nextSibling;
  while (current && current !== end) {
    const next = current.nextSibling;
    parent.removeChild(current);
    current = next;
  }
  parent.insertBefore(content, end);
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

function emitDirectBrowserModule(componentPath: string): string {
  return emitCommand(["emit-browser-direct-js", componentPath]);
}

function emitRuntimeModule(): string {
  return emitCommand(["emit-runtime-js"]);
}

function emitAppBundle(rootPath: string, outDir: string): void {
  emitCommand(["emit-app-legacy", rootPath, outDir]);
}

function emitDirectAppBundle(rootPath: string, outDir: string): void {
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
    "BasicCounterDirect.mjs": emitDirectBrowserModule("examples/basic-counter.weiv"),
    "ConditionalToggleDirect.mjs": emitDirectBrowserModule("examples/conditional-toggle.weiv"),
    "Card.mjs": emitDirectBrowserModule("examples/slots/Card.weiv"),
    "CardToggleUsage.mjs": emitDirectBrowserModule("examples/slots/CardToggleUsage.weiv"),
    "CardUsage.mjs": emitDirectBrowserModule("examples/slots/CardUsage.weiv"),
    "PanelConditionalUsage.mjs": emitDirectBrowserModule("examples/slots/PanelConditionalUsage.weiv"),
    "Panel.mjs": emitDirectBrowserModule("examples/slots/Panel.weiv"),
    "PanelLoopUsage.mjs": emitDirectBrowserModule("examples/slots/PanelLoopUsage.weiv"),
    "PanelNestedCardUsage.mjs": emitDirectBrowserModule("examples/slots/PanelNestedCardUsage.weiv"),
    "PanelToggleUsage.mjs": emitDirectBrowserModule("examples/slots/PanelToggleUsage.weiv"),
    "PanelUsage.mjs": emitDirectBrowserModule("examples/slots/PanelUsage.weiv"),
    "TimerCallbackDirect.mjs": emitDirectBrowserModule("examples/timer-callback.weiv"),
    "TodoListDirect.mjs": emitDirectBrowserModule("examples/todo-list.weiv"),
    "TodoItem.mjs": emitRenderModule("examples/classic-todo/TodoItem.weiv"),
    "TodoList.mjs": emitRenderModule("examples/classic-todo/TodoList.weiv"),
  });

  const basicCounterModule = modules["BasicCounter.mjs"];
  const basicCounterDirectModule = modules["BasicCounterDirect.mjs"];
  const conditionalToggleDirectModule = modules["ConditionalToggleDirect.mjs"];
  const cardDirectModule = modules["Card.mjs"];
  const cardToggleUsageDirectModule = modules["CardToggleUsage.mjs"];
  const cardUsageDirectModule = modules["CardUsage.mjs"];
  const panelConditionalUsageDirectModule = modules["PanelConditionalUsage.mjs"];
  const panelDirectModule = modules["Panel.mjs"];
  const panelLoopUsageDirectModule = modules["PanelLoopUsage.mjs"];
  const panelNestedCardUsageDirectModule = modules["PanelNestedCardUsage.mjs"];
  const panelToggleUsageDirectModule = modules["PanelToggleUsage.mjs"];
  const panelUsageDirectModule = modules["PanelUsage.mjs"];
  const timerCallbackDirectModule = modules["TimerCallbackDirect.mjs"];
  const todoListDirectModule = modules["TodoListDirect.mjs"];
  const todoItemModule = modules["TodoItem.mjs"];
  const todoListModule = modules["TodoList.mjs"];
  const todomvcDirectModules = await loadModules({
    "App.mjs": emitDirectBrowserModule("examples/todomvc/App.weiv"),
    "TodoFooter.mjs": emitDirectBrowserModule("examples/todomvc/TodoFooter.weiv"),
    "TodoHeader.mjs": emitDirectBrowserModule("examples/todomvc/TodoHeader.weiv"),
    "TodoItem.mjs": emitDirectBrowserModule("examples/todomvc/TodoItem.weiv"),
    "TodoList.mjs": emitDirectBrowserModule("examples/todomvc/TodoList.weiv"),
    "TodoTextInput.mjs": emitDirectBrowserModule("examples/todomvc/TodoTextInput.weiv"),
  });
  const todomvcDirectAppModule = todomvcDirectModules["App.mjs"];

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

  const directDocument = new FakeDocument();
  const directTarget = directDocument.createElement("div");
  directDocument.body.append(directTarget);
  (globalThis as any).document = directDocument;

  const directMount = basicCounterDirectModule.mount(directTarget, {
    title: "Counter",
    initialCount: 2,
  });
  if (directTarget.replaceChildrenCalls !== 1) {
    throw new Error(`BasicCounter direct mount expected 1 root replaceChildren call, found ${directTarget.replaceChildrenCalls}`);
  }
  if (!directTarget.textContent.includes("Current count: 2") || !directTarget.textContent.includes("Doubled: 4")) {
    throw new Error("BasicCounter direct mount initial content mismatch");
  }

  const directButton = findElement(directDocument.body, byTag("button"));
  if (!directButton) throw new Error("BasicCounter direct mount missing button");
  click(directButton);

  if (directTarget.replaceChildrenCalls !== 1) {
    throw new Error("BasicCounter direct update rerendered the root instead of patching in place");
  }
  if (!directTarget.textContent.includes("Current count: 3") || !directTarget.textContent.includes("Doubled: 6")) {
    throw new Error("BasicCounter direct click did not patch the updated text");
  }

  for (let i = 0; i < 7; i += 1) {
    click(directButton);
  }
  if (directButton.disabled !== true) {
    throw new Error("BasicCounter direct update did not patch the disabled property");
  }
  if ((directMount.instance.refs as any[]).length === 0) {
    throw new Error("BasicCounter direct mount did not record instance refs");
  }

  const timerDocument = new FakeDocument();
  const timerTarget = timerDocument.createElement("div");
  timerDocument.body.append(timerTarget);
  (globalThis as any).document = timerDocument;

  timerCallbackDirectModule.mount(timerTarget, {});
  if (!timerTarget.textContent.includes("0")) {
    throw new Error("TimerCallback direct mount initial content mismatch");
  }
  const timerButton = findElement(timerDocument.body, byTag("button"));
  if (!timerButton) throw new Error("TimerCallback direct mount missing button");
  click(timerButton);
  await new Promise((resolve) => setTimeout(resolve, 5));
  if (timerTarget.replaceChildrenCalls !== 1) {
    throw new Error("TimerCallback direct timer update rerendered the root");
  }
  if (!timerTarget.textContent.includes("1")) {
    throw new Error("TimerCallback direct timer callback did not patch state");
  }

  const conditionalDocument = new FakeDocument();
  const conditionalTarget = conditionalDocument.createElement("div");
  conditionalDocument.body.append(conditionalTarget);
  (globalThis as any).document = conditionalDocument;

  conditionalToggleDirectModule.mount(conditionalTarget, {});
  if (conditionalTarget.replaceChildrenCalls !== 1) {
    throw new Error(`ConditionalToggle direct mount expected 1 root replaceChildren call, found ${conditionalTarget.replaceChildrenCalls}`);
  }
  if (!conditionalTarget.textContent.includes("Panel is closed")) {
    throw new Error("ConditionalToggle direct mount initial branch mismatch");
  }

  const conditionalButton = findElement(conditionalDocument.body, byTag("button"));
  if (!conditionalButton) throw new Error("ConditionalToggle direct mount missing button");
  click(conditionalButton);

  if (conditionalTarget.replaceChildrenCalls !== 1) {
    throw new Error("ConditionalToggle direct update rerendered the root instead of replacing the conditional block");
  }
  if (!conditionalTarget.textContent.includes("Panel is open")) {
    throw new Error("ConditionalToggle direct toggle did not swap to the open branch");
  }
  if (conditionalTarget.textContent.includes("Panel is closed")) {
    throw new Error("ConditionalToggle direct toggle left the closed branch mounted");
  }

  const panelFallbackDocument = new FakeDocument();
  const panelFallbackTarget = panelFallbackDocument.createElement("div");
  panelFallbackDocument.body.append(panelFallbackTarget);
  (globalThis as any).document = panelFallbackDocument;

  panelDirectModule.mount(panelFallbackTarget, {});
  if (!panelFallbackTarget.textContent.includes("Fallback")) {
    throw new Error("Panel direct mount did not render fallback slot content");
  }

  const panelUsageDocument = new FakeDocument();
  const panelUsageTarget = panelUsageDocument.createElement("div");
  panelUsageDocument.body.append(panelUsageTarget);
  (globalThis as any).document = panelUsageDocument;

  panelUsageDirectModule.mount(panelUsageTarget, { message: "Projected hello" });
  if (!panelUsageTarget.textContent.includes("Projected hello")) {
    throw new Error("PanelUsage direct mount did not render projected default slot content");
  }
  if (panelUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelConditionalUsageDocument = new FakeDocument();
  const panelConditionalUsageTarget = panelConditionalUsageDocument.createElement("div");
  panelConditionalUsageDocument.body.append(panelConditionalUsageTarget);
  (globalThis as any).document = panelConditionalUsageDocument;

  panelConditionalUsageDirectModule.mount(panelConditionalUsageTarget, {});
  if (!panelConditionalUsageTarget.textContent.includes("Projected panel is closed")) {
    throw new Error("PanelConditionalUsage direct mount did not render the initial projected conditional branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Projected panel is open")) {
    throw new Error("PanelConditionalUsage direct mount incorrectly rendered the alternate projected conditional branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelConditionalUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelConditionalButton = findElement(panelConditionalUsageDocument.body, byTag("button"));
  if (!panelConditionalButton) throw new Error("PanelConditionalUsage direct mount missing button");
  click(panelConditionalButton);

  if (panelConditionalUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("PanelConditionalUsage direct update rerendered the root instead of patching the projected conditional branch");
  }
  if (!panelConditionalUsageTarget.textContent.includes("Projected panel is open")) {
    throw new Error("PanelConditionalUsage direct update did not swap to the projected open branch");
  }
  if (panelConditionalUsageTarget.textContent.includes("Projected panel is closed")) {
    throw new Error("PanelConditionalUsage direct update left the previous projected conditional branch mounted");
  }

  const panelLoopUsageDocument = new FakeDocument();
  const panelLoopUsageTarget = panelLoopUsageDocument.createElement("div");
  panelLoopUsageDocument.body.append(panelLoopUsageTarget);
  (globalThis as any).document = panelLoopUsageDocument;

  panelLoopUsageDirectModule.mount(panelLoopUsageTarget, {});
  if (!panelLoopUsageTarget.textContent.includes("Implement template binder") ||
      !panelLoopUsageTarget.textContent.includes("Test CSS scoping")) {
    throw new Error("PanelLoopUsage direct mount did not render the initial projected loop content");
  }
  if (panelLoopUsageTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("PanelLoopUsage direct mount incorrectly rendered the completed projected loop item");
  }
  if (panelLoopUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelLoopUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelLoopButton = findElement(panelLoopUsageDocument.body, byTag("button"));
  if (!panelLoopButton) throw new Error("PanelLoopUsage direct mount missing button");
  click(panelLoopButton);

  if (panelLoopUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("PanelLoopUsage direct update rerendered the root instead of patching projected loop content");
  }
  if (!panelLoopUsageTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("PanelLoopUsage direct update did not swap in the completed projected loop item");
  }
  if (panelLoopUsageTarget.textContent.includes("Implement template binder") ||
      panelLoopUsageTarget.textContent.includes("Test CSS scoping")) {
    throw new Error("PanelLoopUsage direct update left the previous projected loop items mounted");
  }

  const panelNestedCardUsageDocument = new FakeDocument();
  const panelNestedCardUsageTarget = panelNestedCardUsageDocument.createElement("div");
  panelNestedCardUsageDocument.body.append(panelNestedCardUsageTarget);
  (globalThis as any).document = panelNestedCardUsageDocument;

  panelNestedCardUsageDirectModule.mount(panelNestedCardUsageTarget, {});
  if (!panelNestedCardUsageTarget.textContent.includes("Nested dashboard") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested daily overview") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested projected body")) {
    throw new Error("PanelNestedCardUsage direct mount did not render the initial nested slot content");
  }
  if (panelNestedCardUsageTarget.textContent.includes("Untitled") ||
      panelNestedCardUsageTarget.textContent.includes("No body content.") ||
      panelNestedCardUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelNestedCardUsage direct mount incorrectly left fallback content mounted in the nested slot tree");
  }

  const panelNestedCardButton = findElement(panelNestedCardUsageDocument.body, byTag("button"));
  if (!panelNestedCardButton) throw new Error("PanelNestedCardUsage direct mount missing button");
  click(panelNestedCardButton);

  if (panelNestedCardUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("PanelNestedCardUsage direct update rerendered the root instead of patching the nested slot tree");
  }
  if (!panelNestedCardUsageTarget.textContent.includes("Nested reports") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested weekly summary") ||
      !panelNestedCardUsageTarget.textContent.includes("Nested projected report body")) {
    throw new Error("PanelNestedCardUsage direct update did not refresh the nested slot content");
  }
  if (panelNestedCardUsageTarget.textContent.includes("Nested dashboard") ||
      panelNestedCardUsageTarget.textContent.includes("Nested daily overview") ||
      panelNestedCardUsageTarget.textContent.includes("Nested projected body")) {
    throw new Error("PanelNestedCardUsage direct update left the previous nested slot content mounted");
  }

  const panelImperativeDocument = new FakeDocument();
  const panelImperativeTarget = panelImperativeDocument.createElement("div");
  panelImperativeDocument.body.append(panelImperativeTarget);
  (globalThis as any).document = panelImperativeDocument;

  let imperativeMessage = "Imperative projected";
  let imperativeDestroyCalls = 0;
  const imperativeSlot = {
    mountIntoBoundary(start: FakeNode, end: FakeNode) {
      const fragment = panelImperativeDocument.createDocumentFragment();
      const text = panelImperativeDocument.createTextNode(imperativeMessage);
      fragment.append(text);
      replaceBetweenNodes(start, end, fragment);
      return {
        update() {
          text.data = imperativeMessage;
        },
        destroy() {
          imperativeDestroyCalls += 1;
        },
        start,
        end,
      };
    },
  };

  const panelImperativeMount = panelDirectModule.mount(panelImperativeTarget, {}, {}, {
    default: imperativeSlot,
  });
  if (!panelImperativeTarget.textContent.includes("Imperative projected")) {
    throw new Error("Panel direct imperative mount did not render provided slot content");
  }
  if (panelImperativeTarget.textContent.includes("Fallback")) {
    throw new Error("Panel direct imperative mount incorrectly rendered fallback slot content");
  }

  panelImperativeMount.setSlots({});
  panelImperativeMount.update();
  if (!panelImperativeTarget.textContent.includes("Fallback")) {
    throw new Error("Panel direct slot switch did not restore fallback content after removing provided slots");
  }
  if (panelImperativeTarget.textContent.includes("Imperative projected")) {
    throw new Error("Panel direct slot switch left projected content mounted after removing provided slots");
  }
  if (imperativeDestroyCalls !== 1) {
    throw new Error(`Panel direct slot switch expected 1 projected slot destroy call after removing provided slots, found ${imperativeDestroyCalls}`);
  }

  imperativeMessage = "Imperative projected again";
  panelImperativeMount.setSlots({ default: imperativeSlot });
  panelImperativeMount.update();
  if (!panelImperativeTarget.textContent.includes("Imperative projected again")) {
    throw new Error("Panel direct slot switch did not remount provided slot content after restoring slots");
  }
  if (panelImperativeTarget.textContent.includes("Fallback")) {
    throw new Error("Panel direct slot switch left fallback content mounted after restoring provided slots");
  }
  if (panelImperativeTarget.replaceChildrenCalls !== 1) {
    throw new Error("Panel direct slot switching rerendered the root instead of patching the slot boundary");
  }
  panelImperativeMount.destroy();
  if (imperativeDestroyCalls !== 2) {
    throw new Error(`Panel direct destroy expected 2 projected slot destroy calls total, found ${imperativeDestroyCalls}`);
  }
  if (panelImperativeTarget.textContent !== "") {
    throw new Error("Panel direct destroy did not clear the mounted boundary content");
  }

  const panelToggleUsageDocument = new FakeDocument();
  const panelToggleUsageTarget = panelToggleUsageDocument.createElement("div");
  panelToggleUsageDocument.body.append(panelToggleUsageTarget);
  (globalThis as any).document = panelToggleUsageDocument;

  panelToggleUsageDirectModule.mount(panelToggleUsageTarget, {});
  if (!panelToggleUsageTarget.textContent.includes("Projected first")) {
    throw new Error("PanelToggleUsage direct mount did not render the initial projected slot content");
  }
  if (panelToggleUsageTarget.textContent.includes("Fallback")) {
    throw new Error("PanelToggleUsage direct mount incorrectly left fallback slot content mounted");
  }

  const panelToggleButton = findElement(panelToggleUsageDocument.body, byTag("button"));
  if (!panelToggleButton) throw new Error("PanelToggleUsage direct mount missing button");
  click(panelToggleButton);

  if (panelToggleUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("PanelToggleUsage direct update rerendered the root instead of patching projected slot content");
  }
  if (!panelToggleUsageTarget.textContent.includes("Projected second")) {
    throw new Error("PanelToggleUsage direct update did not refresh the projected slot content");
  }
  if (panelToggleUsageTarget.textContent.includes("Projected first")) {
    throw new Error("PanelToggleUsage direct update left the previous projected slot content mounted");
  }

  const cardFallbackDocument = new FakeDocument();
  const cardFallbackTarget = cardFallbackDocument.createElement("div");
  cardFallbackDocument.body.append(cardFallbackTarget);
  (globalThis as any).document = cardFallbackDocument;

  cardDirectModule.mount(cardFallbackTarget, {});
  if (!cardFallbackTarget.textContent.includes("Untitled") || !cardFallbackTarget.textContent.includes("No body content.")) {
    throw new Error("Card direct mount did not render named/default fallback slot content");
  }

  const cardUsageDocument = new FakeDocument();
  const cardUsageTarget = cardUsageDocument.createElement("div");
  cardUsageDocument.body.append(cardUsageTarget);
  (globalThis as any).document = cardUsageDocument;

  cardUsageDirectModule.mount(cardUsageTarget, {
    title: "Dashboard",
    eyebrow: "Daily overview",
    body: "Projected card body",
  });
  if (!cardUsageTarget.textContent.includes("Dashboard") ||
      !cardUsageTarget.textContent.includes("Daily overview") ||
      !cardUsageTarget.textContent.includes("Projected card body")) {
    throw new Error("CardUsage direct mount did not render named/default projected slot content");
  }
  if (cardUsageTarget.textContent.includes("Untitled") || cardUsageTarget.textContent.includes("No body content.")) {
    throw new Error("CardUsage direct mount incorrectly left fallback slot content mounted");
  }

  const cardToggleUsageDocument = new FakeDocument();
  const cardToggleUsageTarget = cardToggleUsageDocument.createElement("div");
  cardToggleUsageDocument.body.append(cardToggleUsageTarget);
  (globalThis as any).document = cardToggleUsageDocument;

  cardToggleUsageDirectModule.mount(cardToggleUsageTarget, {});
  if (!cardToggleUsageTarget.textContent.includes("Dashboard") ||
      !cardToggleUsageTarget.textContent.includes("Daily overview") ||
      !cardToggleUsageTarget.textContent.includes("Projected card body")) {
    throw new Error("CardToggleUsage direct mount did not render the initial named/default projected slot content");
  }
  if (cardToggleUsageTarget.textContent.includes("Untitled") || cardToggleUsageTarget.textContent.includes("No body content.")) {
    throw new Error("CardToggleUsage direct mount incorrectly left fallback slot content mounted");
  }

  const cardToggleButton = findElement(cardToggleUsageDocument.body, byTag("button"));
  if (!cardToggleButton) throw new Error("CardToggleUsage direct mount missing button");
  click(cardToggleButton);

  if (cardToggleUsageTarget.replaceChildrenCalls !== 1) {
    throw new Error("CardToggleUsage direct update rerendered the root instead of patching named/default projected slot content");
  }
  if (!cardToggleUsageTarget.textContent.includes("Reports") ||
      !cardToggleUsageTarget.textContent.includes("Weekly summary") ||
      !cardToggleUsageTarget.textContent.includes("Projected report body")) {
    throw new Error("CardToggleUsage direct update did not refresh the named/default projected slot content");
  }
  if (cardToggleUsageTarget.textContent.includes("Dashboard") ||
      cardToggleUsageTarget.textContent.includes("Daily overview") ||
      cardToggleUsageTarget.textContent.includes("Projected card body")) {
    throw new Error("CardToggleUsage direct update left the previous named/default projected slot content mounted");
  }

  const todoListDirectDocument = new FakeDocument();
  const todoListDirectTarget = todoListDirectDocument.createElement("div");
  todoListDirectDocument.body.append(todoListDirectTarget);
  (globalThis as any).document = todoListDirectDocument;

  todoListDirectModule.mount(todoListDirectTarget, { title: "Tasks" });
  if (todoListDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error(`TodoList direct mount expected 1 root replaceChildren call, found ${todoListDirectTarget.replaceChildrenCalls}`);
  }
  if (!todoListDirectTarget.textContent.includes("Showing pending tasks")) {
    throw new Error("TodoList direct mount initial conditional branch mismatch");
  }
  if (!todoListDirectTarget.textContent.includes("Implement template binder") ||
      !todoListDirectTarget.textContent.includes("Test CSS scoping")) {
    throw new Error("TodoList direct mount initial visible items mismatch");
  }
  if (todoListDirectTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("TodoList direct mount still shows completed item in pending mode");
  }

  const todoListDirectButton = findElement(todoListDirectDocument.body, byTag("button"));
  if (!todoListDirectButton) throw new Error("TodoList direct mount missing toggle button");
  click(todoListDirectButton);

  if (todoListDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoList direct toggle rerendered the root instead of replacing only list/conditional blocks");
  }
  if (!todoListDirectTarget.textContent.includes("Showing completed tasks")) {
    throw new Error("TodoList direct toggle did not switch the conditional branch");
  }
  if (!todoListDirectTarget.textContent.includes("Write parser fixtures")) {
    throw new Error("TodoList direct toggle did not swap in the completed-item list");
  }
  if (todoListDirectTarget.textContent.includes("Implement template binder")) {
    throw new Error("TodoList direct toggle left pending items mounted");
  }

  const todomvcDirectDocument = new FakeDocument();
  const todomvcDirectTarget = todomvcDirectDocument.createElement("div");
  todomvcDirectDocument.body.append(todomvcDirectTarget);
  (globalThis as any).document = todomvcDirectDocument;

  todomvcDirectAppModule.mount(todomvcDirectTarget, { title: "todos" });
  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error(`TodoMVC direct mount expected 1 root replaceChildren call, found ${todomvcDirectTarget.replaceChildrenCalls}`);
  }

  let directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map((element) => element.textContent.trim());
  if (directLabels.length !== 5) {
    throw new Error(`TodoMVC direct mount expected 5 labels, found ${directLabels.length}`);
  }

  const directNewTodoInput = findElement(todomvcDirectDocument.body, byClass("newtodo"));
  if (!directNewTodoInput) throw new Error("TodoMVC direct mount missing newtodo input");
  directNewTodoInput.value = "Direct DOM codegen path";
  keydown(directNewTodoInput, "Enter");

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct create flow rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map((element) => element.textContent.trim());
  if (directLabels[0] !== "Direct DOM codegen path") {
    throw new Error("TodoMVC direct create flow did not prepend the new todo");
  }

  let directFilterButtons = findElements(todomvcDirectDocument.body, byTag("button")).filter((element) =>
    ["All", "Active", "Completed"].includes(element.textContent.trim())
  );
  const directActiveButton = directFilterButtons.find((element) => element.textContent.trim() === "Active");
  if (!directActiveButton) throw new Error("TodoMVC direct active filter button missing");
  click(directActiveButton);

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct filter change rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map((element) => element.textContent.trim());
  if (directLabels.some((text) => text.includes("Port TodoMVC into the verification suite"))) {
    throw new Error("TodoMVC direct active filter still shows completed items");
  }

  const directEditLabel = findElements(todomvcDirectDocument.body, byTag("label")).find((element) =>
    element.textContent.includes("Exercise edit, filter, and clear-completed flows")
  );
  if (!directEditLabel) throw new Error("TodoMVC direct edit target label missing");
  dblclick(directEditLabel);

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct edit-mode entry rerendered the root");
  }
  const directEditInput = findElement(todomvcDirectDocument.body, byClass("edit"));
  if (!directEditInput) throw new Error("TodoMVC direct edit flow did not open edit input");
  directEditInput.value = "Direct path edit flow";
  keydown(directEditInput, "Enter");

  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map((element) => element.textContent.trim());
  if (!directLabels.includes("Direct path edit flow")) {
    throw new Error("TodoMVC direct edit flow did not persist the updated text");
  }

  const directToggles = findElements(todomvcDirectDocument.body, byClass("toggle"));
  const directCreatedToggle = directToggles[0];
  if (!directCreatedToggle) throw new Error("TodoMVC direct toggle flow missing active toggle");
  directCreatedToggle.checked = true;
  change(directCreatedToggle);

  if (todomvcDirectTarget.replaceChildrenCalls !== 1) {
    throw new Error("TodoMVC direct toggle flow rerendered the root");
  }
  directLabels = findElements(todomvcDirectDocument.body, byTag("label")).map((element) => element.textContent.trim());
  if (directLabels.includes("Direct DOM codegen path")) {
    throw new Error("TodoMVC direct active filter did not drop toggled completed item");
  }

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

  const todomvcDirectBundleDir = mkdtempSync(join(tmpdir(), "weiv-todomvc-direct-bundle-"));
  try {
    emitDirectAppBundle("examples/todomvc/App.weiv", todomvcDirectBundleDir);
    const directBundleModule = await importModule(join(todomvcDirectBundleDir, "bundle.mjs"));
    const directBundleMain = readFileSync(join(todomvcDirectBundleDir, "main.mjs"), "utf8");
    if (!directBundleMain.includes("AppBundle.mount(target, props);")) {
      throw new Error("TodoMVC direct bundle missing browser bootstrap");
    }

    const directBundleDocument = new FakeDocument();
    const directBundleTarget = directBundleDocument.createElement("div");
    directBundleDocument.body.append(directBundleTarget);
    (globalThis as any).document = directBundleDocument;

    directBundleModule.mount(directBundleTarget, { title: "todos" });
    if (directBundleTarget.replaceChildrenCalls !== 1) {
      throw new Error(`TodoMVC direct bundle mount expected 1 root replaceChildren call, found ${directBundleTarget.replaceChildrenCalls}`);
    }

    const bundledDirectNewTodoInput = findElement(directBundleDocument.body, byClass("newtodo"));
    if (!bundledDirectNewTodoInput) throw new Error("TodoMVC direct bundle missing newtodo input");
    bundledDirectNewTodoInput.value = "Direct app bundle path";
    keydown(bundledDirectNewTodoInput, "Enter");

    const bundledDirectLabels = findElements(directBundleDocument.body, byTag("label")).map((element) => element.textContent.trim());
    if (bundledDirectLabels[0] !== "Direct app bundle path") {
      throw new Error("TodoMVC direct bundle create flow did not prepend the new todo");
    }
  } finally {
    rmSync(todomvcDirectBundleDir, { recursive: true, force: true });
  }

  process.stdout.write("render checks passed\n");
}

await main();
