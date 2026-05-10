import { test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  FakeDocument,
  byClass,
  byTag,
  byTagAndClass,
  change,
  click,
  dblclick,
  emitAppBundle,
  emitDirectBrowserModule,
  findElement,
  findElements,
  importModule,
  installDocument,
  keydown,
  loadModules,
} from "./support";

test("classic app bundles and helper-copy flows stay healthy", async () => {
  const bundleDir = mkdtempSync(join(tmpdir(), "weiv-app-bundle-"));
  try {
    emitAppBundle("test/examples/classic-todo/App.weiv", bundleDir);
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
    if (typeof bundleModule.mount !== "function") {
      throw new Error("Classic todo bundle missing mount export");
    }
    if (!bundleModule.root?.scopeId || !bundleModule.components?.TodoList?.scopeId || !bundleModule.components?.TodoItem?.scopeId) {
      throw new Error("Classic todo bundle missing scoped component metadata");
    }
  } finally {
    rmSync(bundleDir, { recursive: true, force: true });
  }

  const counterBundleDir = mkdtempSync(join(tmpdir(), "weiv-counter-bundle-"));
  try {
    emitAppBundle("test/examples/basic/basic-counter.weiv", counterBundleDir);
    const counterProps = readFileSync(join(counterBundleDir, "props.mjs"), "utf8");
    if (!counterProps.includes('title: "Preview"') || !counterProps.includes("initialCount: 0")) {
      throw new Error("BasicCounter bundled props.mjs missing inferred preview props");
    }
  } finally {
    rmSync(counterBundleDir, { recursive: true, force: true });
  }

  const importedHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-helper-bundle-"));
  try {
    emitAppBundle("test/examples/imported-helper/App.weiv", importedHelperBundleDir);
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
    if (typeof importedHelperBundle.mount !== "function" || !importedHelperBundle.root?.scopeId) {
      throw new Error("Imported helper bundle missing direct bundle contract");
    }
  } finally {
    rmSync(importedHelperBundleDir, { recursive: true, force: true });
  }

  const importedTsHelperBundleDir = mkdtempSync(join(tmpdir(), "weiv-imported-ts-helper-bundle-"));
  try {
    emitAppBundle("test/examples/imported-ts-helper/App.weiv", importedTsHelperBundleDir);
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
    if (typeof importedTsHelperBundle.mount !== "function" || !importedTsHelperBundle.root?.scopeId) {
      throw new Error("Imported TS helper bundle missing direct bundle contract");
    }
  } finally {
    rmSync(importedTsHelperBundleDir, { recursive: true, force: true });
  }
}, 120_000);

test("TodoMVC direct modules and app bundle behave correctly", async () => {
  const modules = await loadModules({
    "App.mjs": emitDirectBrowserModule("test/examples/todomvc/App.weiv"),
    "TodoFooter.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoFooter.weiv"),
    "TodoHeader.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoHeader.weiv"),
    "TodoItem.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoItem.weiv"),
    "TodoList.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoList.weiv"),
    "TodoTextInput.mjs": emitDirectBrowserModule("test/examples/todomvc/TodoTextInput.weiv"),
    "ClassicTodoItem.mjs": emitDirectBrowserModule("test/examples/classic-todo/TodoItem.weiv"),
    "ClassicTodoList.mjs": emitDirectBrowserModule("test/examples/classic-todo/TodoList.weiv"),
  });

  const todomvcDirectAppModule = modules["App.mjs"];
  const classicTodoItemModule = modules["ClassicTodoItem.mjs"];
  const classicTodoListModule = modules["ClassicTodoList.mjs"];

  if (!classicTodoItemModule.css.includes(`[data-weiv-scope="${classicTodoItemModule.scopeId}"] .todo-item`)) {
    throw new Error("TodoItem CSS scope mismatch");
  }
  if (!classicTodoListModule.css.includes(`[data-weiv-scope="${classicTodoListModule.scopeId}"] .todo-list`)) {
    throw new Error("TodoList CSS scope mismatch");
  }

  const todomvcDirectDocument = new FakeDocument();
  const todomvcDirectTarget = todomvcDirectDocument.createElement("div");
  todomvcDirectDocument.body.append(todomvcDirectTarget);
  installDocument(todomvcDirectDocument);

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

  const todomvcBundleDir = mkdtempSync(join(tmpdir(), "weiv-todomvc-bundle-"));
  try {
    emitAppBundle("test/examples/todomvc/App.weiv", todomvcBundleDir);
    const todomvcBundle = await importModule(join(todomvcBundleDir, "bundle.mjs"));
    const todomvcStyles = readFileSync(join(todomvcBundleDir, "styles.css"), "utf8");
    if (!todomvcStyles.includes(".todo-header") ||
        !todomvcStyles.includes(".todo-footer") ||
        !todomvcStyles.includes(".toggle-all") ||
        !todomvcStyles.includes(".newtodo")) {
      throw new Error("TodoMVC bundle missing expected selectors");
    }
    if (typeof todomvcBundle.mount !== "function") {
      throw new Error("TodoMVC bundle missing mount export");
    }

    const fakeDocument = new FakeDocument();
    const appTarget = fakeDocument.createElement("div");
    appTarget.setAttribute("id", "app");
    fakeDocument.body.append(appTarget);
    installDocument(fakeDocument);

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
    emitAppBundle("test/examples/todomvc/App.weiv", todomvcDirectBundleDir);
    const directBundleModule = await importModule(join(todomvcDirectBundleDir, "bundle.mjs"));
    const directBundleMain = readFileSync(join(todomvcDirectBundleDir, "main.mjs"), "utf8");
    if (!directBundleMain.includes("AppBundle.mount(target, props);")) {
      throw new Error("TodoMVC direct bundle missing browser bootstrap");
    }

    const directBundleDocument = new FakeDocument();
    const directBundleTarget = directBundleDocument.createElement("div");
    directBundleDocument.body.append(directBundleTarget);
    installDocument(directBundleDocument);

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
}, 120_000);
