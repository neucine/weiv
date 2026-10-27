# Weiv integration friction

## Published 0.1.1 external callbacks require `queueMicrotask` (2026-10-27)

- **Classification:** released-package/version documentation gap. The latest guide now distinguishes current-source `weivUpdate` from the published 0.1.1 workaround.
- **Context:** CC GUI command palette, `weivjs@0.1.1`, local Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduction:** in `src/weiv/CommandPalette.weiv`, register a window `keydown` listener from a queued initialization and call `weivUpdate(togglePalette)` for Ctrl+K. Run the Vite fixture at `http://localhost:1420/tests/browser/weiv-timeline-search.html`, focus the page, and press Ctrl+K.
- **Expected:** the latest `packages/weiv/README.md` says published 0.1.1 must schedule external state changes through its wrapped `queueMicrotask`; current source supports `weivUpdate`.
- **Actual:** the fixture accessibility tree shows `ReferenceError: weivUpdate is not defined` with the generated handler at `CommandPalette.weiv`, and the palette does not open.
- **Workaround:** use `queueMicrotask(() => { togglePalette(); })` for window listeners and the same wrapper for registry subscriptions. The browser fixture then opened the palette with Ctrl+K, filtered commands, updated from a dynamically registered command, executed local and registered commands, navigated with arrows, wrapped Tab focus, and closed with Escape.
- **Upgrade check:** when moving to a package that provides `weivUpdate`, replace the 0.1.1 microtask workaround and retest native WKWebView.

## Native WKWebView accessibility exposes only the first command option (2026-10-27)

- **Classification:** WKWebView/Weiv accessibility interoperability gap; browser behavior is correct and the root cause is not yet isolated.
- **Context:** CC GUI command palette, packaged `CC GUI Weiv Preview.app`, `weivjs@0.1.1`, macOS arm64.
- **Reproduction:** build the isolated preview, launch it, focus the Weiv web content, press Cmd+K, and inspect the native macOS accessibility tree. The screenshot visibly contains Open Settings, Search chats, New chat, Toggle Files panel, Toggle Changes panel, Toggle terminal, Split right, Split down and Exit split view.
- **Expected:** every visible option with `role="option"` is exposed as a native accessibility child.
- **Actual:** the full native tree lists the dialog and a list containing only `text Open Settings`; the remaining visible buttons are absent from the accessibility tree. The Chrome browser fixture exposes every option. Keyboard ArrowDown plus Enter still runs the second visible command and Escape still closes the palette, so mouse and keyboard behavior works despite the tree omission.
- **Workaround:** none applied. Native keyboard operation remains available; a future cleanup should replace the list container/button structure with an accessibility arrangement verified by macOS VoiceOver.

## Nested Git row template expression scoping (2026-10-27)

- **Classification:** compiler/template-expression issue; precise minimal root cause not yet isolated.
- **Context:** CC GUI Weiv Changes panel, `weivjs@0.1.1`, Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduction:** in `GitChanges.weiv`, nest `#for="row in group.rows"` inside `#for="group in props.view.groups"`; inside the row use conditions such as `#if="row.isDir"` and a computed attribute `:style="'padding-left:' + (row.depth * 14) + 'px'"`. Run `corepack pnpm build`, then open `tests/browser/weiv-timeline-search.html?manyChanges=1` and open Changes.
- **Expected:** the mounted directory/file rows render with their indentation.
- **Actual:** the build passed, but the Weiv error boundary showed `ReferenceError: row is not defined`, and the Changes body was partially rendered.
- **Workaround:** project `indentStyle` and `groupId` as simple row properties in `git-changes-view.ts`, then bind `:style="row.indentStyle"` and `:data-group="row.groupId"`. The 2,000-file browser fixture then showed bounded rows and worked on deep scroll. This narrows the problem to template expression or nested-loop scoping but does not prove which expression caused the error.

This report records reproducible Weiv integration and tooling friction. No
external issue has been submitted.

## External event listener ownership (2026-10-21)

- **Classification:** confirmed compiler analysis defect, fixed in current source.
- **Context:** `.weiv` component with local state, macOS arm64, Zig 0.16.0,
  Bun 1.2.16, Weiv checkout based on `8470b95`.
- **Reproduction:** in a component script, register
  `window.addEventListener("change", () => { count += 1; })` and render
  `{{ count }}`. Dispatch the event after mounting.
- **Expected:** the analyzer marks this callback unowned or the runtime wraps
  it so the text updates.
- **Actual:** the Rust analyzer marked every `.addEventListener` callback as
  owned, while the generated component did not wrap script-registered listeners.
  The DOM kept the prior count after dispatch. There was no build error output.
- **Fix and workaround:** the analyzer now marks these listeners unowned.
  Place the mutation inside `weivUpdate(() => { count += 1; })` to flush it.
  A DOM regression and analyzer test cover both behaviors.

## Compiler toolchain selection (2026-10-21)

- **Classification:** tooling and documentation gap, not a confirmed compiler defect.
- **Context:** checking a browser backend file-organization refactor at the
  current checkout. macOS arm64, Bun 1.2.16, Homebrew Zig 0.17.0 on `PATH`.
- **Reproduction:** run `zig build test` from the repository root with Zig
  0.17.0. `bun test test/inspect` reaches the same build error because its
  tests invoke the compiler through `zig build`.
- **Expected:** the repository states or selects the Zig version needed to
  build it, and the documented test command uses that version.
- **Actual:** `build.zig:51:11: error: no field named 'args' in struct 'Build'`
  (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig:1:1: note: struct declared here`).
- **Workaround:** install Homebrew `zig@0.16` and run
  `PATH=/opt/homebrew/opt/zig@0.16/bin:$PATH zig build test`. This passed.
  The mismatch is reproducible; no Weiv source change is needed for this refactor.

The following sections record friction found while building the interactive
Roam, Muse, and Hearth demos with Weiv.

## Environment

- Task: build a browser UI that completes the Roam workflow end to end.
- App component: `apps/roam/src/ui/App.weiv` (648 lines, 32,226 bytes).
- Weiv package: `weivjs@0.1.0`.
- Weiv source inspected at commit: `94c330880876969c3dd414c62ad8fad05d6a48ff`.
- Node.js: `v22.22.1`.
- Bun: `1.2.16`.
- Zig: `0.16.0`.
- OS: macOS `26.6.2` (`25G83`), Apple Silicon.

## Summary

| Finding | Fixing status | Classification | Impact | Workaround used |
| --- | --- | --- | --- | --- |
| `if` nested in `for` uses the wrong ref scope | **Fixed in 0.1.1** | Confirmed code-generation/runtime defect | Later list entries and following UI can disappear | Replace the conditional node with text/class bindings |
| State assigned after `await` does not refresh immediately | **Fixed in 0.1.1; original app not rerun** | Async boundary limitation or documentation gap | Server changes succeed but the visible UI remains stale | Apply post-`await` changes inside `queueMicrotask` |
| `bind:value` is not two-way despite two-way-binding terminology | **Resolved by documentation in 0.1.1** | API naming/documentation gap | Forms submit stale component state | Add an explicit `on:input` handler |
| `:global(...)` is emitted as scoped CSS | **Fixed in 0.1.1** | Missing capability or compiler defect | Root variables and body styles do not apply | Scope variables to the app and put shell CSS in the host page |
| Full-app emit/package-runner builds were killed | **Open — environment-sensitive, not reproduced** | Tooling/resource interoperability issue | Normal package scripts could not reliably build this component | Invoke split JS/CSS compilation with the direct shell script |
| Successful validation prints allocator leak errors | **Fixed in 0.1.1** | Confirmed tooling defect | Clean CI output is impossible and a real leak may be hidden | None; command still exits zero |
| Reactive `for` updates duplicate entries in Muse | **Fixed in 0.1.1; current-source regression added** | Confirmed in published 0.1.0 runtime | A changing constellation corrupts its DOM | Render fixed-cardinality nodes explicitly |
| Runtime expression fallbacks require `unsafe-eval` | **Fixed in current source; unreleased** | Security/tooling incompatibility | Strict-CSP apps fail when an expression cannot be compiled directly | Use directly rewritable expressions or named handlers |
| Native label `for` is parsed as a loop | **Fixed in 0.1.1** | HTML interoperability/documentation gap | Standard label association does not compile | Nest the control inside the label |
| Bare element selectors lose the descendant combinator | **Fixed in current source; unreleased** | Confirmed CSS-emission defect in `weivjs@0.1.0` | Emitted CSS is invalid | Narrow post-compile repair |
| Current docs and installed directive syntax differ | **Resolved in 0.1.1 and weiv.dev** | Documentation/version discoverability gap | Compilation succeeds but structural regions all render | Use the installed package's compatibility syntax |
| Dynamic style binding is blocked by strict CSP | **Fixed in current source; unreleased** | Weiv/CSP interoperability defect | Dynamic layout declarations have no effect when inline styles are disallowed | Use scoped classes |
| Generated app import maps are blocked by strict CSP | **Fixed in current source; unreleased** | Weiv/CSP bundling incompatibility | Apps with bare imports fail to resolve their dependencies | Allow the inline import map or bundle/rewrite bare imports |
| Vue structural syntax is accepted as inert HTML | **Fixed in current source** | Migration/tooling diagnostics gap | A list or conditional silently renders once as static markup | Replace `v-for`/`v-if` with `#for`/`#if` and verify the packaged UI |
| Loop event expressions resolve component functions from loop scope | **Fixed in current source; browser regression passes** | Confirmed in published 0.1.1 runtime | Per-item actions silently do nothing | Decorate each item with a callback and explicitly invoke it |
| Async list-item updates do not refresh repeated bindings | **Fixed in current source for declared async helpers** | Confirmed async reactivity defect in `weivjs@0.1.1` | Asynchronously enriched item attributes remain stale | Update the model and the rendered element, or route scalar writes through a synchronous helper |
| Conditional blocks do not mount after later state changes | **Fixed in current source; exact Framecept regression passes** | Confirmed in the earlier Framecept integration state | Inspectors and empty states remain stuck in their initial branch | Keep both states mounted and toggle visibility synchronously |
| Dynamic class binding replaces static classes | **Fixed in current source** | Confirmed attribute-merging defect in `weivjs@0.1.1` | Base styling disappears when the binding updates | Return the complete class string from one binding |

## 1. Conditional nodes inside loops lose loop-local scope

**Fixing status:** Fixed in `0.1.1` and covered by a browser regression.

### Minimal pattern

```html
<article #for="strategy in data.strategies">
  <h3>{{ strategy.title }}</h3>
  <i #if="strategy.id === data.brief.selectedStrategyId">✓</i>
</article>
```

### Reproduction

1. Render a list containing at least two strategies.
2. Put an `if` node inside the repeated element, with a condition that reads the
   loop item.
3. Compile and mount the component.

### Expected

Every strategy renders, and the mark appears only on the selected strategy.

### Actual

The first entry rendered, then later entries and subsequent page sections were
missing. In generated JavaScript, the loop creates entry-local refs, but the
conditional updater reads the component's root `instance.refs`. Removing the
nested conditional restored the complete page.

### Workaround

Keep the node mounted and bind its content and visibility instead:

```html
<i :class="'selected-mark' + (strategy.id === selectedId ? ' visible' : '')">
  {{ strategy.id === selectedId ? "✓" : "" }}
</i>
```

This appears to be a compiler/runtime defect, not a project incompatibility.

## 2. Post-`await` state changes occur outside the reactive boundary

**Fixing status:** Fixed in `0.1.1` and covered by an async mutation regression;
the original Roam request sequence was not rerun because its fixture is absent.

### Minimal pattern

```ts
async function load() {
  const next = await api("/api/state");
  data = next;
}

async function selectStrategy(id: string) {
  busy = true;
  await api("/api/select", { strategyId: id });
  await load();
  busy = false;
}
```

### Reproduction

1. Trigger `selectStrategy` from a Weiv event handler.
2. Confirm that the API response contains the new selected strategy.
3. Observe the selection indicator without reloading the page.

### Expected

Assignments after `await` invalidate dependent bindings and update the DOM.

### Actual

The backend state changed, but the selected strategy and busy state stayed stale
until a full reload. The generated event boundary completes synchronously when
the handler returns its Promise; later assignments therefore run outside that
boundary.

### Workaround

Schedule the state application through a wrapped asynchronous primitive:

```ts
const next = await api("/api/state");
queueMicrotask(() => applyState(next));
```

The UI then updates immediately. If async event handlers are intentionally not
tracked, this needs prominent documentation and a first-class recommended
pattern; otherwise it is a runtime defect.

## 3. `bind:value` is one-way despite two-way-binding terminology

**Fixing status:** Resolved as a documentation/API-expectation issue in `0.1.1`;
one-way binding remains intentional.

### Minimal pattern

```html
<input :value="draftOrigin" />
```

### Reproduction

1. Initialize `draftOrigin` from component state.
2. Edit the input in the browser.
3. Submit a form that reads `draftOrigin`.

### Expected

The edited input value is reflected in `draftOrigin`, as the `bind:value`
spelling commonly implies.

### Actual

The visible input changed, but the submitted value remained the initial value.
Weiv examples pair `bind:value` with explicit input/change handlers, but the
quick-start material did not make the one-way semantics clear.

### Workaround

```html
<input :value="draftOrigin" @input="updateOrigin" />
```

```ts
function updateOrigin(event: Event) {
  draftOrigin = (event.currentTarget as HTMLInputElement).value;
}
```

This may be intentional API behavior, but the directive name and missing
explanation caused avoidable integration time.

## 4. Scoped CSS does not provide a working `:global(...)` escape

**Fixing status:** Fixed in `0.1.1` with compiler regression coverage.

### Minimal pattern

```css
:global(:root) {
  --ink: #193047;
}

:global(body) {
  margin: 0;
}
```

### Reproduction

1. Put the CSS above in a `.weiv` component.
2. Emit the component CSS.
3. Inspect the generated selectors and load the page.

### Expected

The compiler emits `:root` and `body`, or documents another supported way to
write global shell styles.

### Actual

The output retained `:global(...)` behind the component scope, for example:

```css
[data-weiv-scope="..."]:global(:root),
[data-weiv-scope="..."] :global(:root)
```

Browsers did not apply the rules, so CSS variables fell back and the page lost
its intended color system.

### Workaround

Define variables on the scoped app root and keep the small `html`, `body`, and
mount-point reset in the host page. This works, but splits component styling
across two sources.

## 5. Full-app emit and package-runner builds were killed

**Fixing status:** Open. The failure appears environment-sensitive and has not
been reproduced without the original Roam fixture.

### Reproduction A: full-app emit

```sh
node_modules/.bin/weiv compile emit app apps/roam/src/ui/App.weiv /tmp/output
```

When invoked through the original Bun package script, the result was:

```text
$ weiv compile emit app src/ui/App.weiv public
error: script "build:ui" was terminated by signal SIGKILL (Forced quit)
```

### Reproduction B: split compilation under a package runner

The split compiler commands work when the script is executed directly, but the
same script under `bun run` was killed:

```text
scripts/build-ui.sh: line 10: 54082 Killed: 9 "$compiler" compile emit js "$package_directory/src/ui/App.weiv" > "$output_directory/App.mjs"
error: script "build:ui" exited with code 137
```

### Expected

A 32 KB component compiles through the documented full-app path and ordinary
package scripts without being terminated.

### Actual

Full-app emit was killed. Split JS/CSS compilation succeeded only when the shell
script was invoked directly. Another Zig process was consuming substantial
memory during part of the investigation, so this finding may be
environment-sensitive and should not yet be labeled a deterministic Weiv bug.

### Workaround

The checked-in build path is:

```sh
sh apps/roam/scripts/build-ui.sh
```

It emits JavaScript and CSS separately and has been reliable in this workspace.

## 6. Successful validation reports allocator leaks

**Fixing status:** Fixed in `0.1.1`; validation now frees transferred
diagnostics without allocator leak output.

### Reproduction

```sh
node_modules/.bin/weiv compile validate app apps/roam/src/ui/App.weiv --json
```

### Expected

The validator exits zero with JSON diagnostics and no allocator errors.

### Actual

The command exits `0`, reports `"ok": true`, and then writes the following
complete allocator error output (addresses vary between runs):

```text
error(gpa): memory address 0x104fe0640 leaked:

error(gpa): memory address 0x104fe0660 leaked:

error(gpa): memory address 0x104fe0680 leaked:

error(gpa): memory address 0x104fe06a0 leaked:

error(gpa): memory address 0x1005630c0 leaked:

error(gpa): memory address 0x100563100 leaked:

error(gpa): memory address 0x100563140 leaked:

error(gpa): memory address 0x100563180 leaked:

error(gpa): memory address 0x104f53980 leaked:

error(gpa): memory address 0x104f53a80 leaked:

error(gpa): memory address 0x104f53b00 leaked:

error(gpa): memory address 0x104f53b80 leaked:

error(gpa): memory address 0x104f69000 leaked:
```

The local source compiler also emitted allocator leak diagnostics from paths
including `DiagnosticBag.appendOwned`, `appendBindingDiagnostics`,
`compileReport`, `Graph.collectValidated`, and `validateApp` while still
producing output. This is reproducible tooling noise and likely a real cleanup
defect.

## Result

None of these findings blocked the finished demo. With the workarounds above,
the UI supports trip creation, strategy selection, approval/hold creation, and
navigation without a reload.

## Repository follow-up (2026-10-11)

- Fixed nested structural regions by preserving the caller's ref scope through
  conditional and loop helpers. A browser regression covers initial rendering
  and an async state change for an `if` nested in a `for`.
- Confirmed that current owned-event boundaries flush again when a returned
  Promise settles. The regression mutates the selected item after `await`
  without using the reported `queueMicrotask` workaround. The original Roam app
  is not present in this checkout, so its exact request sequence was not rerun.
- Documented the intentionally one-way semantics of `bind:value` and the
  explicit input-event pattern in the package README.
- Fixed whole-selector `:global(...)` emission and added compiler coverage for
  global and ordinary scoped selectors in the same component.
- Reproduced validation leaks with `test/examples/kanib/App.weiv`. The app graph
  discarded the diagnostic slice while transferring a successful compile
  report, preventing its destructor from freeing those allocations. The
  transfer now frees diagnostics first; validation completes without allocator
  leak output.
- The full-app/package-runner SIGKILL report remains environment-sensitive and
  was not reproduced from the absent Roam fixture.

## Muse follow-up (2026-10-12)

### Environment

- Task: build Muse's interactive spatial constellation and guided Spark loop.
- App component: `apps/muse/src/ui/App.weiv` in the Harngine repository.
- Weiv package: `weivjs@0.1.0` (`@weivjs/weiv-darwin-arm64@0.1.0`).
- Node.js: `v22.22.1`.
- TypeScript: `5.9.3`.
- Browser: Chromium 155 embedded browser.
- OS: macOS arm64.

### 7. Reactive `for` loops append duplicate entries

**Fixing status:** Fixed in `0.1.1` by the nested structural ref-scope repair;
current-source real-DOM regression coverage also protects plain loop appends.

#### Minimal reproduction

```html
<template>
  <button for="node in nodes" on:click="select(node.id)">
    {{ node.title }}
    <i if="node.evidence.length > 0">{{ node.evidence.length }} trace</i>
  </button>
</template>
<script>
  let nodes = [{ id: "a", title: "A", evidence: ["hash"] }];
  let selected = "";
  function select(id) { selected = id; }
</script>
```

1. Compile with `weiv compile emit js App.weiv`.
2. Mount the emitted component.
3. Click the loop-rendered button so reactive state updates.

Expected: selection updates and the loop retains one DOM entry per array item.

Actual: the nested conditional update throws, and later dirty-region passes
append duplicate loop entries. A plain message `for` loop without a nested
conditional also appended a second copy when its backing array gained an item,
so the reconciliation issue is broader than the conditional crash:

```text
TypeError: Cannot read properties of undefined (reading 'parentNode')
    at replaceBetween (App.mjs:2:24)
    at updateConditional_* (App.mjs:983:5)
    at updateRegion_conditional_* (App.mjs:1971:3)
    at update (App.mjs:870:5)
    at createForEntry_* (App.mjs:919:3)
    at updateForLoop_* (App.mjs:937:16)
```

Workaround: Muse renders its eight known reference nodes explicitly. Its
conversation renders the latest exchange in a stable element. The append-only
lineage still uses `for` because it does not mutate while mounted. This prevents
a general dynamic constellation until stable keyed reconciliation is available.

This overlaps finding 1, which is fixed in the repository after 0.1.0. Retest
the broader plain-loop append case against the current source before closing it.

### 8. Runtime expression fallbacks require `unsafe-eval`

**Fixing status:** Fixed in current source; unreleased. Directly rewritable
calls such as `selectNode(node.id)` compile to ordinary JavaScript and execute
inside the owned reactive boundary. The emitter no longer includes the
`Function(...)` runtime evaluator: expressions that cannot be resolved by the
static paths fail emission instead of requiring `unsafe-eval`. The shared
resolver is used by text interpolation, attribute binding, structural regions,
child props, and DOM or child-component handlers; this is not limited to event
expressions.

- Classification: security/tooling incompatibility and documentation gap.
- Reproduction: compile `on:click="selectNode(node.id)"`, serve with
  `Content-Security-Policy: script-src 'self' 'unsafe-inline'`, and click it.
- Expected: emitted code calls the in-scope function without runtime code
  generation.
- Actual: emitted `__weiv_evaluate` calls `Function(...)`; Chromium blocks it
  because `unsafe-eval` is absent.

```text
EvalError: Evaluating a string as JavaScript violates Content Security Policy
    at Function (<anonymous>)
    at __weiv_evaluate (App.mjs:10:10)
```

Workaround: keep the strict CSP and expose named zero-argument handlers such as
`select0` and `select1`. Named handler references compile without runtime
evaluation. Muse does not weaken its CSP with `unsafe-eval`.

### 9. Native label `for` is parsed as a loop directive

**Fixing status:** Fixed in `0.1.1`; structural directives now require `#for`,
so bare `for` remains a native HTML attribute.

- Classification: HTML interoperability and diagnostics gap.
- Reproduction: add `<label for="seed-question">Question</label>` to a valid
  component.
- Expected: `for` is emitted as the native label/input association attribute.
- Actual: compilation halts with `template.invalid_directive` at an offset that
  does not identify the label. The compiler reserves every `for` attribute for
  loop syntax.
- Workaround: Muse nests the textarea inside its label so the accessible
  association remains intact. An explicit `htmlFor` or escaped-attribute form
  should be documented or supported for standard accessible forms.

## Hearth integration follow-up (2026-10-12)

### Environment

- Task: build Hearth's ambient home-world UI as a Weiv single-file component.
- Installed package: `weivjs@0.1.0`.
- Weiv source inspected at commit: `c06e21bdc13da4dde9907d66463a1c36b8710e49`.
- Node.js: `v22.22.1`.
- Bun: `1.2.16`.
- OS: macOS on Apple Silicon.
- App component: `harngine/apps/hearth/src/ui/App.weiv`.

### 10. Bare-element selectors emit invalid CSS

**Fixing status:** Fixed in current source with selector-list and pseudo-class
regressions; not yet released.

- Classification: confirmed compiler CSS-emission defect in the installed package.
- Minimal reproduction:

```weiv
<template>
  <header><button>Hello</button></header>
</template>

<style>
  button, input, textarea { font: inherit; }
  header { display: flex; }
</style>
```

Run from the Harngine workspace:

```sh
node_modules/.bin/weiv compile emit css apps/hearth/src/ui/App.weiv
```

Expected valid descendant selectors:

```css
[data-weiv-scope="…"] button,
[data-weiv-scope="…"] input,
[data-weiv-scope="…"] textarea { font: inherit; }
[data-weiv-scope="…"] header { display: flex; }
```

Actual output concatenates the scope attribute directly with the element:

```css
[data-weiv-scope="…"]button,
[data-weiv-scope="…"]input,
[data-weiv-scope="…"]textarea { font: inherit; }
[data-weiv-scope="…"]header { display: flex; }
```

Biome reports:

```text
expected `,` but instead found `button`
expected `,` but instead found `input`
expected `,` but instead found `textarea`
expected `,` but instead found `header`
expected `,` but instead found `aside`
expected `,` but instead found `main`
```

Workaround: `harngine/apps/hearth/scripts/build-ui.sh` performs a narrow post-compile repair. It
inserts the missing descendant combinator only between Weiv's generated scope attribute and the
affected bare HTML element selectors. The source remains a standard Weiv component.

### 11. Current documentation and installed directive syntax differ

**Fixing status:** Resolved by the `0.1.1` release and matching `weiv.dev`
documentation. Projects pinned to `0.1.0` must use that version's syntax.

- Classification: documentation/version discoverability gap.
- Expected from the inspected current source documentation: `#if`, `#for`, `:name`, and `@event`
  compile as structural directives, bindings, and handlers.
- Actual in the installed `weivjs@0.1.0`: compilation succeeds, but those spellings are emitted as
  literal DOM attributes, leaving every structural region visible at once.
- Workaround: use the installed package's compatibility spellings—`if`, `for`, `bind:name`, and
  `on:event`—which compile into the intended conditional regions, loops, bindings, and handlers.

A versioned syntax table or compiler diagnostic would expose the mismatch before browser testing.

### 12. Dynamic style binding is blocked by strict CSP

**Fixing status:** Fixed in current source; unreleased. The root cause was Weiv
writing a dynamic style binding with `setAttribute("style", value)`, which
Chromium rejects under Hearth's `style-src 'self'` policy. The emitter now uses
the CSSOM `element.style.cssText` setter. Chromium accepts that setter under the
same policy and the browser performs declaration parsing without Weiv needing a
second CSS parser.

- Classification: confirmed browser-visible binding defect in the installed package.
- Reproduction: bind a string such as `left:58%;width:60px` with
  `bind:style="bloomStyle(bloom)"`.
- Expected: the declarations appear in `element.style.cssText` and affect layout.
- Actual: `outerHTML` contains the expected `style` attribute text, but
  `element.style.cssText` is empty and the declarations do not affect layout. The same result was
  observed with CSS custom properties and ordinary declarations. Class and text bindings in the
  same loop update correctly.
- Workaround: keep dynamic meaning in class bindings, express the four seed-memory garden
  positions as scoped CSS classes, and use stable scoped CSS for weather visuals.

### Related compact-control handler finding

A `for` directive on Pulse preset buttons rendered the expected controls, but the argument-bearing
click handler did not update the bound input in browser QA. This overlaps Muse finding 8: named,
zero-argument handlers avoid runtime expression evaluation and work under the strict CSP. Hearth
therefore renders its four Pulse starters and five energy values explicitly with named handlers.

No external issue was submitted for these Hearth findings.

### 13. Generated app import maps are blocked by strict CSP

**Fixing status:** Fixed in current source; unreleased. App emission no longer
writes an inline `<script type="importmap">`. Bare imports are rewritten to a
same-origin `__weiv_packages` endpoint, and the generated Bun server resolves,
browser-bundles, and caches each requested package.

- Classification: confirmed Weiv/CSP bundling incompatibility.
- Reproduction: emit an app containing a bare import, serve its generated HTML
  with `Content-Security-Policy: script-src 'self'`, and load it in Chromium.
- Expected: the external application module and its dependencies load without
  requiring `unsafe-inline`.
- Actual: Chromium rejects the import map and reports
  `TypeError: Failed to resolve module specifier` when the bare import is used.
- Current-source verification: the generated HTML contains no inline import
  map, and an HTTP request to the generated server returned a browser-bundled
  workspace package with `Content-Type: text/javascript` and status 200.
- Custom static hosting must provide equivalent files for the rewritten package
  endpoint; the generated Bun server supplies it automatically.

## Repository follow-up (2026-10-12)

- Retested reactive generic loops against current source with a real DOM. A
  regression now selects an item through an argument-bearing loop handler,
  appends a fourth item, and verifies that all four keyed entries occur exactly
  once while the nested conditional remains stable. The broader duplication
  report was not reproduced after the nested structural ref-scope fix shipped
  in `0.1.1`.
- Confirmed a related owned-boundary defect for call-expression handlers.
  Current source already rewrote `@click="selectNode(node.id)"` directly and did
  not emit `Function(...)`, but it evaluated the call before entering
  `runOwnedBoundary`. The emitter now evaluates both DOM and child-component
  handler expressions inside the owned boundary, so their mutations flush and
  directly rewritable calls remain compatible with strict CSP.
- Confirmed that the canonical structural grammar in `0.1.1` leaves bare
  `for`, `if`, and `else` as ordinary HTML attributes. Native
  `<label for="...">` therefore compiles without an escape or workaround.
- Reproduced the bare-element CSS defect in current source. Root matches now
  insert the scope attribute after the type selector—for example,
  `button[data-weiv-scope="..."]`—while descendant matches retain the required
  space. Compiler coverage includes selector lists and a type selector with a
  pseudo-class.
- Published `weivjs@0.1.1` and updated `weiv.dev` document the canonical `:`,
  `@`, and `#` syntax plus the temporary `bind:`/`on:` compatibility warnings.
  The documentation mismatch remains relevant only when a project installs
  `0.1.0` while reading current docs.
- Retested dynamic `:style` against current source in jsdom. The declaration
  text appears in the attribute and in `element.style.cssText`, with parsed
  `left` and `width` values, but jsdom does not enforce Hearth's CSP. A minimal
  Chromium reproduction using `style-src 'self'` confirms the original symptom:
  `setAttribute("style", ...)` retains raw attribute text while the CSSOM stays
  empty. The same declarations applied with either `style.cssText` or
  `style.setProperty(...)` populate the CSSOM. Weiv now emits the `cssText`
  setter, preserving string-binding replacement semantics without manually
  decomposing declarations. Static `style="..."` template attributes now use
  the same CSSOM path instead of `setAttribute`.

## Framecept integration follow-up (2026-10-14)

### Environment

- Task: migrate the Framecept Qt desktop shell, media library, and timeline
  list to Weiv.
- Weiv source: sibling checkout at `/Users/chao.yang/Private/weiv`.
- Weiv package: `weivjs@0.1.1`.
- Node.js: `26.6.0`.
- Vite: `7.3.7`.
- TypeScript: `5.9.3`.
- Tauri: `2.12.3`.
- OS: macOS.

### 14. Vue structural syntax is accepted as inert HTML

**Fixing status:** Fixed in current source. The binder now emits targeted
`directive.vue_structural_syntax` warnings, and the Vite integration forwards
them during production builds. This was a migration diagnostic opportunity,
not a runtime defect. The current documentation correctly specifies `#for` and
`#if`.

#### Minimal reproduction

```html
<template>
  <li v-for="item in items">{{ item.title }}</li>
  <p v-if="items.length === 0">No items</p>
</template>
```

1. Add `v-for` or `v-if` to an element in a `.weiv` template.
2. Run the application's Vite production build (`vite build`).
3. Open the packaged application and inspect the affected list or conditional
   region.

Expected: the compiler or Vite integration reports a non-fatal migration
warning explaining that Vue structural syntax is an ordinary inert HTML
attribute in Weiv and that `#for` or `#if` is required.

Actual: the build succeeds without a warning or error. The element renders once
as static markup, so the mistake is discovered only while interacting with the
packaged UI. There is no error output to include because compilation exits
successfully.

Workaround: replace Vue-style attributes with Weiv structural directives and
verify the populated list or conditional state in the packaged application:

```html
<template>
  <li #for="item in items">{{ item.title }}</li>
  <p #if="items.length === 0">No items</p>
</template>
```

A targeted warning for the exact attribute names `v-for` and `v-if` would catch
a common migration error while preserving Weiv's general support for ordinary
custom HTML attributes.

### 15. Loop event expressions cannot resolve outer component functions

**Fixing status:** Fixed in current source; the published `weivjs@0.1.1`
behavior remains relevant. A real-DOM regression now invokes an
argument-bearing component helper from a generic loop and verifies the state
and nested conditional update.

#### Minimal pattern

```html
<button #for="asset in media" @click="addAssetById(asset.id)">
  Add to V1
</button>
```

```ts
async function addAssetById(id: number) {
  // Add the selected media asset to the timeline.
}
```

Expected: the click expression resolves the component-level function and
passes the current loop item's ID.

Actual: generated code calls
`loopScope.addAssetById(loopScope.asset.id)`. The repeated scope contains
`asset`, but not the outer component function, so clicking produces no state
change or visible diagnostic.

A related form, `@click="asset.addToTimeline"`, only evaluates the decorated
callback reference. It does not invoke the function and also produces no
visible diagnostic.

Workaround: decorate each loop item with a callback in component code and
explicitly invoke it from the event expression:

```ts
const decoratedMedia = media.map((asset) => ({
  ...asset,
  addToTimeline: () => addAssetById(asset.id),
}));
```

```html
<button #for="asset in decoratedMedia" @click="asset.addToTimeline()">
  Add to V1
</button>
```

This keeps every identifier resolved from the loop item while making the call
explicit. The finding is a confirmed event-scope defect, not a documentation
gap.

### 16. Async list-item updates do not refresh repeated bindings

**Fixing status:** Fixed in current source for component-declared `async
function` helpers. Reproduced with `weivjs@0.1.1`; this was a narrower case than
the post-`await` report in finding 2 because the async helper's Promise was
explicitly discarded by its caller.

#### Minimal pattern

```html
<img #for="asset in media" :src="asset.thumbnailUrl" alt="" />
```

```ts
async function loadThumbnail(asset: MediaAsset) {
  const url = await requestThumbnail(asset.id);
  media = media.map((candidate) =>
    candidate.id === asset.id ? { ...candidate, thumbnailUrl: url } : candidate,
  );
}
```

Expected: replacing the array after the host request refreshes the repeated
item's bound `src` attribute.

Actual: the generated async function leaves the assignment untracked, so the
model changes but the DOM retains the original attribute value. Scalar writes
after `await`, such as clearing a busy state, show the same behavior in this
integration.

Workaround: retain the model update and directly update the already-rendered
thumbnail after the host request resolves. For scalar assignments, routing the
write through a synchronous component function restores the reactive update.

This was a confirmed reactivity defect affecting async list enrichment. The
setup emitter now wraps declared async helpers in the component's owned
boundary, so completion is observed even when a caller uses
`void loadMissingThumbnails()`. A real-DOM regression replaces the array after
`await` and verifies the repeated image's `src` changes from `pending` to
`ready`.

### 17. Conditional blocks do not mount after a later state change

**Fixing status:** Fixed in current source. Originally reproduced with
`weivjs@0.1.1` at source commit
`87a52836c28a72dc72706c760483eefab76b7152`, plus the local scoped-CSS and event
fixes then present.

#### Minimal pattern

```html
<section #if="selectedId >= 0">Selected clip</section>
<section #if="selectedId < 0">No clip selected</section>
```

```ts
let selectedId = -1;

function selectClip(id: number) {
  selectedId = id;
}
```

1. Mount the component while `selectedId` is `-1`.
2. Assign a positive ID from a button click.
3. Run the Vite production build inside Tauri and select a clip.

Expected: the selected section mounts and the empty-state section unmounts.

Actual: adjacent text bindings update to the selected clip, but the structural
branches remain in their initial state. The initially false section stays
absent and the initially true empty-state section stays mounted.

Workaround: keep both inspector states mounted, toggle their visibility from a
synchronous selection helper, and update the timing text through the same
helper.

The exact Framecept shape now has real-DOM coverage: a callback stored on a loop
item selects a clip, the initially-false top-level conditional mounts, and the
inverse empty-state conditional unmounts. The current owned event-boundary
changes fixed this path; no additional structural emitter change was needed.

### 18. Dynamic class binding replaces static classes

**Fixing status:** Fixed in current source; reproduced in published
`weivjs@0.1.1`.

#### Minimal pattern

```html
<button class="clip" :class="selected ? 'selected' : ''">Clip</button>
```

Expected: the dynamic class is merged with the static class, producing either
`clip` or `clip selected`.

Actual: the generated binding replaces the complete `class` attribute. When
the expression evaluates to `selected`, the base `clip` class and its styling
are removed.

Workaround: return the complete class string from a single binding:

```html
<button :class="selected ? 'clip selected' : 'clip'">Clip</button>
```

This was a confirmed attribute-merging defect in `0.1.1`. Current source keeps
the static class tokens while applying and clearing the dynamic class value.

## Repository follow-up (2026-10-14)

- Added `directive.vue_structural_syntax` binder warnings for the exact
  attributes `v-if` and `v-for`. The Vite plugin now forwards non-fatal compiler
  warnings during its transform, and a production-build regression verifies the
  migration guidance reaches the user.
- Added static/dynamic class merging in the browser emitter. A real-DOM
  regression verifies `class="clip"` combined with a changing `:class` binding
  produces `clip`, then `clip selected`, then `clip` again.
- Retested `@click="selectStrategy(strategy.id)"` inside `#for` against current
  source. The component helper resolves through the loop scope and runs inside
  the owned boundary; the existing real-DOM regression verifies the selection
  and nested conditional update. No additional resolver change was needed.
- Added an exact Framecept reactivity fixture. It verifies that a loop-item
  callback mounts an initially-false top-level conditional and removes the
  inverse empty state; current event-boundary handling already passes this case.
- Wrapped component-declared async function helpers in the owned boundary at
  setup time. The same fixture calls a thumbnail loader with `void`, replaces
  its media array after `await`, and verifies the repeated `src` binding updates.
  Async arrow-function bindings are outside this specific repair and should be
  assessed separately if they exhibit the same fire-and-forget pattern.
- Removed the runtime `Function(...)` expression evaluator. The complete example
  corpus emits without it, preserving strict CSP without an `unsafe-eval`
  exception.
- Replaced inline app import maps with same-origin package URLs. The generated
  Bun server resolves and browser-bundles bare dependencies on demand, caches
  the result, and returns JavaScript without requiring `unsafe-inline`.

## Atelier integration findings (2026-10-27)

These findings were recorded in the local Atelier project while using published `weivjs@0.1.1` with Tauri 2 and Vite 7. The original observations below describe that package; current-source verification follows separately. The source report is `/Users/chao.yang/Private/atelier/WEIV_FRICTION.md`.

### Current-source verification (2026-10-27)

Retested against checkout `1633af0` with the changes in this working tree, Node 22.22.1, Vite 7.3.7, and Zig 0.16.0. These results do not establish what is available in the published `0.1.1` package.

| Atelier finding | Current-source result |
| --- | --- |
| Top-level `const` reassignment | Reproduced; fixed by emitting a mutable internal binding for tracked locals. `node --check` passes. |
| Imported function called before initialization | Fixed by initializing imported aliases before user script execution. A top-level `listen` fixture mounts successfully. |
| Published Vite plugin omits CSS | Current plugin emits CSS. An additional relative `?weiv-style.css` import failure appeared in Atelier and was fixed in the plugin resolver. |
| Call-expression event handler misses update boundary | Focused `@click="selectEngine('codex')"` fixture updates the DOM. |
| Compound expression loses loop scope | Reproduced; fixed by resolving called helpers and loop items through the same scope. Focused fixture mounts and renders `Codex`. |
| `weivUpdate` unavailable in deferred callback | Focused deferred window-event fixture updates the DOM through `weivUpdate` in current source. Published `0.1.1` still emits an unresolved `weivUpdate` reference; its wrapped `queueMicrotask` works as a release-specific workaround. |
| Keyboard listener misses state flush | Direct external listeners need an update boundary. A current-source keyboard fixture works with `weivUpdate`, and a published `0.1.1` fixture works with its wrapped `queueMicrotask`. The package README now distinguishes those versions. |
| Invalid scoped global selectors | Current CSS emitter produces valid selectors for `*`, `body`, and `button`. |
| Conditional sibling loses loop scope | Focused two-message fixture renders both sibling branches correctly. |

The Atelier desktop and remote pages built with the local compiler and Vite plugin. The remote smoke test passed. The desktop smoke test passed after allowing one pending tracked-state microtask to run before closing jsdom; without that test-only wait, its assertions passed but a queued DOM update ran after `dom.window.close()`.

### Release-check binary detection false positive (2026-10-27)

- **Classification:** confirmed release-tooling defect, fixed in this checkout.
- **Context:** preparing `weivjs@0.1.2` on macOS arm64 with Node 22.22.1 and a Zig 0.16.0 `ReleaseFast` compiler binary.
- **Reproduce:** rebuild `packages/weiv-darwin-arm64/bin/weiv` from current source, then run `node tools/npm-release-check.mjs`.
- **Expected:** accept a real Mach-O binary and check only platform packages being published at the main package's version.
- **Actual:** the script decoded binary bytes as UTF-8 and rejected the real executable because embedded text contained `placeholder`. It also attempted to check older platform packages whose checked-in files are intentional placeholders.
- **Fix:** identify ELF, Mach-O, and PE binaries by magic bytes, then pack only platform packages matching the main package version. The release check now passes.

### Top-level `const` rewritten as an assignment

- **Category:** confirmed compiler defect in generated JavaScript; workaround available.
- **Context:** Tauri 2 + Vite 7 app using `weivjs` 0.1.1 on macOS, Node 22.22.1.
- **Reproduce:** place `const projectKey = "atelier.projects.v1";` in a `.weiv` component script and reference it from component logic. Run `npm run build`.
- **Expected:** generated module keeps a valid immutable binding or avoids reassigning it.
- **Actual:** Vite/Rollup reports `Cannot reassign a variable declared with const`. The transformed module contains `projectKey = __weiv_getTrackedRoot("projectKey", projectKey);`.
- **Workaround:** declare the binding with `let`. The build then completes without the warning.
- **Source:** `src/App.weiv`; generated output can be inspected through Vite at `/src/App.weiv?import` during development.

### Top-level call to an imported function runs before initialization

- **Category:** confirmed compiler defect in generated JavaScript; workaround available.
- **Context:** Atelier's Weiv 0.1.1 component imports `listen` from `@tauri-apps/api/event` and registers a listener at script top level. macOS Tauri 2 release webview; Vite 7, Node 22.22.1.
- **Reproduce:** add `import { listen } from "@tauri-apps/api/event";` followed by `listen("run-event", handler);` at top level of a `.weiv` component script. Build with `npm run build`, then run the bundle or evaluate it in a DOM environment.
- **Expected:** imported binding is initialized before the call.
- **Actual:** mount throws `ReferenceError: Cannot access 'listen' before initialization` (minified name `H` in the release bundle), leaving the Tauri window blank. The generated component initialization calls the listener before its tracked import binding is initialized.
- **Workaround:** defer registration with `queueMicrotask(() => listen("run-event", handler))`. The rendered DOM then mounts successfully.
- **Verification:** the release JavaScript was evaluated in jsdom before and after the change; before it threw that error, afterward it rendered the sidebar and welcome text.

### Published Vite plugin omits component styles

- **Category:** packaging/tooling defect in published `weivjs` 0.1.1.
- **Context:** Atelier imports `App.weiv` through `weivjs/vite` with Vite 7.3.7 and packages the result in Tauri 2 on macOS.
- **Reproduce:** create a `.weiv` component with a `<style>` block, import it from a Vite entry, and run `vite build` using the published `weivjs/vite` plugin.
- **Expected:** a CSS asset is emitted and referenced by the built HTML.
- **Actual:** Vite emits only JavaScript; the app renders as unstyled HTML. The installed `node_modules/weivjs/dist/vite.mjs` compiles only `js`, while the newer local Weiv source includes a CSS virtual module path.
- **Workaround:** `vite.config.ts` adds a small virtual CSS loader that invokes `weiv compile emit css` for `App.weiv`, and `src/main.ts` imports that virtual style module. Vite now emits a CSS asset referenced by `dist/index.html`.

### Some event expressions run outside Weiv's update boundary

- **Category:** compiler/runtime integration defect.
- **Context:** Weiv 0.1.1 component with a button using `@click="selectEngine('codex')"`.
- **Reproduce:** in a component, update a template-bound `let selectedEngine` inside `selectEngine`; bind the button using a call expression and click it.
- **Expected:** the selected button and related text update immediately.
- **Actual:** localStorage changed, but template content did not update. Generated code evaluated `instance.refresh().selectEngine("codex")` before checking whether the result was a function to run in Weiv's update boundary.
- **Workaround:** bind a named function, `@click="selectCodex"`, whose body calls `selectEngine("codex")`. The named handler runs inside the update boundary.

### Compound expressions lose component or loop scope

- **Category:** compiler defect in generated JavaScript.
- **Context:** Weiv 0.1.1 template with a conditional conversation view and a `#for` message loop.
- **Reproduce:** bind a placeholder with `:placeholder="'Ask ' + engineName()"`, or render `{{ message.role === 'user' ? 'You' : engineName() }}` inside `#for="message in messages"`.
- **Expected:** both the component function and loop variable resolve correctly.
- **Actual:** the first expression emitted an unscoped `engineName()` and threw `ReferenceError: engineName is not defined` when the conversation view appeared. The second emitted unscoped `message.role` and threw `ReferenceError: message is not defined` when messages rendered.
- **Workaround:** use a static placeholder and keep the loop label expression independent of the component function. The built-app smoke test now covers both transitions.

### `weivUpdate` is unavailable in a deferred external callback

- **Category:** compiler/runtime integration defect.
- **Context:** Tauri event subscription registered in a microtask to avoid the import initialization bug above.
- **Reproduce:** call `weivUpdate(() => { ... })` in the Tauri event callback and deliver a `run-event` message.
- **Expected:** local state changes flush to the component, as described in Weiv's external callback documentation.
- **Actual:** generated code retains `weivUpdate(...)` as an unresolved global and throws `ReferenceError: weivUpdate is not defined`.
- **Workaround:** the external callback stores the event, then clicks a hidden component button bound to the named `applyRunEvent` handler. The state change runs in Weiv's own event boundary. The smoke test delivers session, answer, and done events through this path.

### Window keyboard listeners do not flush component state

- **Category:** runtime integration defect; same external update boundary issue as Tauri event callbacks.
- **Context:** Atelier with Weiv 0.1.1, Vite 7.3.7, Node 22.22.1, Tauri 2; reproduced in the built UI smoke test with jsdom 29.1.1.
- **Reproduce:** register `window.addEventListener("keydown", handler)` from a `.weiv` script via `queueMicrotask`. In the handler, call a component function that updates template-bound state, such as `openFilesPanel()` assigning `panelMode = "files"`. Dispatch Cmd+P.
- **Expected:** the Files panel appears, as it does when its visible Weiv button is clicked.
- **Actual:** the listener runs but the panel is absent because its state changes occur outside Weiv's update boundary. The smoke test failed with `AssertionError: file search shortcut must open Files` and `document.querySelector(".inspector") === null`.
- **Workaround:** the keyboard listener programmatically clicks hidden buttons bound to named Weiv handlers. The same smoke test then passes and the panel appears.

### Scoped style compiler produces invalid global selectors

- **Category:** confirmed compiler/tooling defect in Weiv 0.1.1; workaround available.
- **Context:** Atelier's separate Weiv remote page (`src/Remote.weiv`) with Vite 7.3.7, Node 22.22.1, macOS, and the `weiv compile emit css` workaround for the published Vite plugin.
- **Reproduce:** put `* { box-sizing: border-box; } body { margin: 0; } button { cursor: pointer; }` in a `.weiv` `<style>` block, import its emitted CSS, then run `npm run build:remote`.
- **Expected:** valid scoped CSS or a clear unsupported-global-selector diagnostic.
- **Actual:** esbuild warns `Unexpected "*" [css-syntax-error]` for a selector shaped `[data-weiv-scope="..."]*`, and similarly warns for `body` and `button`; those rules are not applied.
- **Workaround:** anchor the rules under the component root (`.remote-shell *`, `.remote-shell button`) and place document-wide styles outside the scoped component if needed. The remote build then has no CSS warnings.

### Conditional sibling after a looped message body loses loop scope

- **Category:** confirmed generated JavaScript defect in Weiv 0.1.1.
- **Context:** Atelier chat timeline in `src/App.weiv`, Vite 7.3.7, Node 22.22.1, jsdom 29.1.1, macOS. The local Weiv source checkout was at commit `1633af0` during this work; the app uses the published 0.1.1 package.
- **Reproduce:** inside `<article #for="message in messages">`, render a `<div #if="message.role !== 'tool'">` and a following sibling `<details #if="message.role === 'tool'">` with `{{ message.text }}`. Build with `npm run test:ui`, then deliver a chat run event in the smoke test.
- **Expected:** the sibling conditional and interpolation resolve the current `message` loop item.
- **Actual:** the build succeeds, but rendering logs the following error repeatedly and the smoke test fails at `AssertionError: question card must appear` because rendering stops. Removing those sibling conditionals makes the same test pass.

  ```text
  ReferenceError: message is not defined
      at ag (evalmachine.<anonymous>:24:26474)
      at x_ (evalmachine.<anonymous>:17:59015)
      at og (evalmachine.<anonymous>:24:26429)
      at h (evalmachine.<anonymous>:17:52002)
      at l_ (evalmachine.<anonymous>:17:53460)
      at c_ (evalmachine.<anonymous>:17:53720)
      at $m (evalmachine.<anonymous>:24:24220)
      at n_ (evalmachine.<anonymous>:17:49757)
      at na (evalmachine.<anonymous>:24:23669)
      at w1 (evalmachine.<anonymous>:25:15669)
  AssertionError [ERR_ASSERTION]: question card must appear
      at file:///Users/chao.yang/Private/atelier/test/smoke.mjs:128:1
  ```
- **Workaround:** render the standard body and a `<details>` body unconditionally inside the loop, then use the article role class to show the appropriate one with CSS. A compiler fix should preserve loop scope for sibling `#if` nodes.

## CC GUI desktop migration follow-up (2026-10-27)

Context: adding a Weiv chat entry alongside the existing React entry in CC GUI. Environment: macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, `weivjs` 0.1.1.

## Confirmed compiler defect: imported function used before initialization

Reproduction: create a `.weiv` component with `<script lang="ts">import { snapshot } from "./adapter"; let initial = snapshot();</script>`, compile it with `weiv compile emit js`, and mount it. Expected: `snapshot()` runs during setup. Actual: the generated `setup()` calls `snapshot()` before its later `const snapshot = __weiv_getTrackedRoot(...)` declaration. Chrome reports `ReferenceError: Cannot access 'snapshot' before initialization`, leaving only root comment nodes in the page. Workaround in `src/weiv/App.weiv`: initialize local values without the import, then read the store in a queued microtask after setup completes. The fallback text in `src/weiv/main.ts` also prevents a silent blank page if mounting throws again.

## Tooling gap: component styles are omitted by the Vite plugin

Reproduction: add `<style>.example { color: red }</style>` to a `.weiv` component, import the component through `weivjs/vite`, and build with Vite. Expected: the component's CSS appears in the page. Actual: the emitted JavaScript includes the component, but the CSS is absent. Current workaround: keep shared styles in `src/weiv/app.css` and import that file from `src/weiv/main.ts`. An earlier workaround called `weiv compile emit css` through a local Vite plugin, but splitting the UI made a normal stylesheet simpler.

## Tooling gap: sibling component imports do not resolve in Vite

Reproduction: create `Parent.weiv` with `import * as Child from "./Child.weiv"` and `<Child />`, then run Vite build with `weivjs/vite`. Expected: Vite bundles both components. Actual: Weiv emits `import * as Child from "./Child.mjs"`, and Vite reports `Could not resolve "./Child.mjs" from "Parent.weiv"`. Workaround: the small `ccgui-weiv-component-imports` Vite resolver maps an emitted local `.mjs` import back to an existing `.weiv` source.

## Compiler defect: object shorthand in component props emits invalid JavaScript

Reproduction: pass `:view="{ open, page }"` to a child component and run `weiv compile emit js Parent.weiv`. Expected: generated JS uses `open: scope.open, page: scope.page`. Actual: it emits `{ scope.open, scope.page }`, which Rollup rejects with `Unexpected token '.'`. Workaround: spell every object key explicitly, such as `:view="{ open: open, page: page }"`.

## Compiler defect: child component in a conditional branch can update before mount

Reproduction: put `<Child :view="{ value: value }" />` inside a `#if="selected"` section, change `selected` from false to true, and update the parent. Expected: Child mounts and receives props. Actual: the generated `updateRegion_child` calls `refs[index].setProps(...)` while that ref is undefined, throwing `Cannot read properties of undefined (reading 'setProps')`. Workaround: keep the chat section mounted and bind its native `hidden` attribute; CSS hides `[hidden]` without tearing down the child component.

## Compiler defect: complex prop member expression can remain unscoped

Reproduction: in a child component, use `:disabled="(!props.view.draft.trim() && !props.view.attachments.length) || !props.view.hasActiveChat"`. Expected: generated render code resolves `props` through `scope`. Actual: it emits bare `props.view...` in the initial render and throws `ReferenceError: props is not defined`. Workaround: derive `sendDisabled` in the parent and bind the child attribute to `props.view.sendDisabled`.

The same unscoped expression occurred in a Settings `#if` combining `!props.view.settingsQuery` with `String.includes(props.view.settingsQuery)`. Deriving simple `showGeneral` / `showClaude` / `showCodex` booleans in the parent avoided the crash.

## Diagnostics gap: HTML void tags reported as mismatched close at template start

Reproduction: add `<label>Name<input name="name"></label>` to a Weiv template and run `weiv compile emit js`. Expected: the parser accepts the HTML void tag or points at the input that needs closing. Actual: compilation stops with `error template.mismatched_close_tag [template_parse] [1:11] [10..11] fatal: Closing tag does not match the currently open element`, which points at the beginning of `<template>` rather than the offending input. Workaround: write `<input name="name" />` explicitly. This is a diagnostics and HTML compatibility gap, not a confirmed runtime defect.

## Confirmed reactivity gap: assignments after await do not repaint

Reproduction: in a `.weiv` event handler, call an async function that sets `busy = true`, awaits an IPC promise, then sets `busy = false` and replaces a list used by `#for`. Expected: the busy state clears and the list repaints when the promise settles. Actual: the busy indicator stays visible and the list keeps its old rows even though the backend mutation and reload finish. A no-op DOM event dispatched afterward also fails because Weiv takes its before-snapshot after the lexical assignments have already occurred. Workaround: keep the `mount()` handle and call its public `update()` method after async assignments (`src/weiv/ui-refresh.ts`). Verified with a mocked Tauri IPC flow that saved a provider profile and then displayed its row.

## Loop identity can recreate a streaming message row

In the emitted `#for` code for `message in messages`, the key is `item?.id ?? item`. Chat messages have `seq` but no `id`; an immutable update to a live message therefore changes the object key and replaces that row's DOM. This can reset selection or an expanded tool output while text streams. Workaround in `src/weiv/chat-adapter.ts`: project each message to a stable `id` based on session key and sequence, caching unchanged source messages in a `WeakMap`. This is an integration constraint of the default loop key, not a confirmed compiler defect.

These reports are local engineering notes; no external issue was submitted.

## Packaged app CSP incompatibility: component prop objects use runtime evaluation

Context: packaging the Weiv 0.1.1 entry in Tauri 2.11.5 on macOS arm64 with the project's production CSP (`script-src 'self' blob: pluginasset: http://pluginasset.localhost`). Reproduction: build `weiv.html` with Vite, package it as the Tauri window URL, then launch the `.app`. Expected: the compiled component props mount under the existing CSP. Actual: the window displays `EvalError: Refused to evaluate a string as JavaScript because 'unsafe-eval' or 'trusted-types-eval' is not an allowed source of script`. `weiv compile emit js src/weiv/App.weiv` showed that inline object-valued component props called `__weiv_evaluate`, which uses the `Function` constructor; the production asset contained the same fallback. Workaround verified: move each object expression into a named component function and bind `:view="timelineView()"` rather than an inline object. The generated Weiv entry asset then contained no `Function(...)` call or runtime fallback warning. The unsigned macOS preview launched under the normal CSP and restored a transcript, opened Settings, and searched the transcript in WKWebView. This is a Weiv compiler/runtime capability gap in published 0.1.1; the local Weiv checkout reports a fix in current source.

## Project-specific Tauri preview window conflict

Context: the same isolated native preview. Reproduction: override `app.windows` with a `main` window in `tauri.weiv.bundle.conf.json` while `src-tauri/src/lib.rs` also creates `main` during setup, then package and launch. Expected: one Weiv window. Actual: startup aborts with `failed to create main window: WebviewLabelAlreadyExists("main")`. Workaround: keep `app.windows` empty and choose `weiv.html` in the existing window builder when the preview bundle identifier is active. This is a project integration issue rather than a Weiv defect.

## Template compatibility gap: HTML entity is shown literally

Context: the Weiv 0.1.1 settings rail on macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. Reproduction: put `<div>WORKSPACE &amp; DATA</div>` in a `.weiv` template, build with `corepack pnpm build`, and mount it in Chrome via Vite. Expected: the accessible text and rendered heading say `WORKSPACE & DATA`. Actual: the browser accessibility tree says `WORKSPACE &amp; DATA`. Workaround tried and retained: use `WORKSPACE AND DATA` in the template. This is an HTML entity compatibility gap, not a settings data defect.

## Compiler defect: local const is reassigned during setup

Context: adding collapsible workspace groups to `App.weiv`, same Weiv 0.1.1 macOS/Node/pnpm/Vite environment above. Reproduction: declare `const collapsedGroups = new Set<string>();` in a component script and read it from a function used by the template. Build succeeds, but mounting the component throws `TypeError: Assignment to constant variable.` The emitted `setup()` contains `collapsedGroups = __weiv_getTrackedRoot("collapsedGroups", collapsedGroups);` after the original `const` declaration. Expected: the compiler preserves `const` or uses a separate binding. Actual: it writes to the constant. Workaround: declare the set with `let`; a browser fixture then mounts. This is a confirmed compiler defect.

## Compiler defect: type-only named import becomes a runtime reference

Context: adding `SessionSearch.weiv` to the Weiv 0.1.1 entry. In `App.weiv`, add `import { ipc, type MessageSearchHit } from "@/lib/ipc";` and use `MessageSearchHit[]` only as a TypeScript annotation. Build with `corepack pnpm build` and open `weiv.html`. Expected: the type import is erased and the app mounts. Actual: the build succeeds, but mounting throws `ReferenceError: __weiv_import_MessageSearchHit is not defined`, shown by the app's error fallback. Workaround: import only the runtime `ipc` value and use a local structural type for the search hits. This was verified by rerunning the mocked Tauri UI smoke: mount, chat send, provider save, theme switch, and search IPC call then worked without runtime exceptions.

The same defect recurred in `Sidebar.weiv` during worktree progress migration with a pure `import type { PendingCreation } from "@/features/worktree/store";` and `PendingCreation[]` as a function return type. `corepack pnpm build` and a Tauri debug bundle both succeeded, but the native WKWebView error fallback showed `ReferenceError: Can't find variable: __weiv_import_PendingCreation`. Replacing the import with a local structural `type PendingCreation = { ... }` is the workaround. This confirms the problem also affects standalone `import type`, not only inline `type` specifiers.

## Investigation: nested worktree progress loop coincides with duplicate sidebar rows

Context: CC GUI's `Sidebar.weiv` on Weiv 0.1.1, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, Tauri 2.11.5, macOS arm64. Add a pending worktree `#for` inside an existing nested `#for` over workspace sections/workspaces, with `#if="workspace.children.length || pendingFor(workspace.id).length"`, where `pendingFor` filters a prop array. Build and launch the native preview, then open a workspace action menu and select New Worktree. Expected: one workspace row and a creation dialog. Actual observed: every UI refresh appended another visible copy of the workspace row and its session row; the dialog did not appear. The browser fixture exposed the cause: `ReferenceError: workspace is not defined` at `updateConditional_55`, and emitted JS contains `Boolean(workspace.children.length || scope.pendingFor(workspace.id).length)` inside a scope where only `scope.workspace` exists. Classification: **confirmed compiler scoping defect** for a nested-loop condition calling a function with the loop item. Workaround: project `pending` onto each workspace node in TypeScript, then use `#if="workspace.children.length || workspace.pending.length"` and `#for="pending in workspace.pending"`. After that change, the browser fixture renders one workspace row and opens the creation dialog. Native retest is pending. No external issue submitted.

The same unscoped expression defect occurred in `WorktreeDelete.weiv` with `{{ props.view.locked || props.actions.text('worktree.lockedDeleteDisabled') }}`. `weiv compile emit js` produced `String((props.view.locked || props.actions.text(...)) ?? "")` instead of `scope.props`, and native WKWebView showed `ReferenceError: Can't find variable: props` on opening the delete dialog. Workaround: compute `lockedLabel` in its TypeScript controller and bind `{{ props.view.lockedLabel }}`. The regenerated JS has no bare `props` expression at that text binding. The native preview then showed the Git lock reason and kept Delete disabled; after unlocking the disposable worktree, deletion succeeded.

The existing-branch tab in `WorktreeCreate.weiv` hit a similar failure with `{{ props.view.occupied.includes(branch.name) ? ' · checked out' : '' }}` inside an `<option #for="branch in ...">`. The browser fixture reported `ReferenceError: props is not defined` at `updateRegion_text_45`; the emitted JS used bare `props.view.occupied` and `branch.name`. The native selector consequently showed a branch but did not advance the form. Workaround: project `{ name, label, occupied }` branch options in the TypeScript controller and bind the simple `branch.label` and `branch.occupied` properties. The fixture then displayed the suggested location and enabled Create after choosing the existing branch; the native preview also created a worktree from that retained branch. A follow-up UI issue showed the selector visually reverting to its placeholder even though the controller kept the selected branch. Explicit `:selected` bindings on projected option properties fixed that display in the browser fixture and in the packaged macOS WKWebView preview: selecting `feature/select-smoke` kept the branch name visible and filled the corresponding location. The test dialog was canceled and the disposable branch removed.

### Diagnostics gap: malformed TypeScript silently discards the component script

- **Classification:** confirmed compiler diagnostics defect in published `weivjs@0.1.1`; current source was not yet retested.
- **Context:** `Sidebar.weiv` in the CC GUI Tauri migration, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Minimal reproduction:** create `<template><button @click="click">Go</button></template><script lang="ts">let id = "a"; let rows: any[] = []; function click() { rows.some((row: any) => row.id === id; }</script>` (the call deliberately lacks a closing `)`). Run `weiv compile emit js component.weiv`.
- **Expected:** a syntax diagnostic and nonzero exit, pointing to the unmatched parenthesis.
- **Actual:** exit status 0 with no diagnostic output. The emitted `setup()` contains only the generated `props` binding; `click` and all other component script declarations are omitted. The page mounts but its buttons silently do nothing. In the CC GUI case, the malformed expression had 8 opening and 7 closing parentheses; `corepack pnpm build` succeeded and the browser fixture showed no action after clicking.
- **Workaround:** simplify the expression, fix the syntax, and inspect generated JavaScript for expected functions. The corrected `Sidebar.weiv` emitted `function showWorkspaceMenu` and the browser action worked.

## Integration gap: boolean data binding does not round-trip as string "true"

- **Classification:** template/DOM interoperability gap in published `weivjs@0.1.1`; no compiler defect established.
- **Context:** CC GUI React-to-Weiv file tree, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. The row click handler distinguishes folders from files using a `data-*` value.
- **Reproduce:** render `<button :data-dir="row.isDir" @click="openRow">Open</button>` inside `#for="row in props.view.rows"`, with `row.isDir === true`. In `openRow`, read `(event.currentTarget as HTMLElement).dataset.dir === "true"` and click the folder in the browser fixture `tests/browser/weiv-timeline-search.html`.
- **Expected:** the dataset comparison is true and the folder expands, or the binding documentation makes the boolean-to-attribute conversion explicit.
- **Actual:** the comparison is false; clicking `src` calls the file-open path and creates a `src` editor tab. The generated attribute is not a dependable string `"true"` for this handler.
- **Workaround:** project `kind: row.isDir ? "dir" : "file"` in `src/weiv/file-tree-view.ts`, bind `:data-kind="row.kind"`, and compare with `"dir"`. The browser fixture then expanded `src` and displayed its `main.ts` child. No private workspace content is needed for reproduction.
The type-only import defect recurred during Git-list virtualization (macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3, `weivjs@0.1.1`, Weiv checkout `1633af0`). In `src/weiv/App.weiv`, `import { projectGitChanges, type GitListMode } from "./git-changes-view"; let gitViewMode = "tree" as GitListMode;` passed `corepack pnpm build`, but the Chrome fixture `tests/browser/weiv-timeline-search.html?manyChanges=1` failed at mount with `ReferenceError: __weiv_import_GitListMode is not defined` in generated `setup()`. Expected: the type-only binding is erased. Removing the imported type and its assertion restored mounting. This is the same confirmed compiler defect described above.


## Packaged diff rows overlapped with per-row absolute positioning

- **Classification:** Weiv/Tauri production rendering interoperability gap; the exact compiler or WKWebView cause is not established, so this is not a confirmed Weiv defect.
- **Context:** CC GUI Weiv Git diff migration, `weivjs@0.1.1` (local Weiv checkout `1633af0`), macOS arm64 WKWebView in Tauri, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. Chrome Vite fixture rendered the same diff correctly.
- **Reproduce:** in `GitDiff.weiv`, render projected diff rows with `#for="line in props.view.lines"`, bind each row's `:style="line.style"` where `line.style` is `top:0px`, `top:20px`, etc., and set `.git-diff-line { position:absolute; height:20px }`. Build with `corepack pnpm exec tauri build --debug --bundles app --config src-tauri/tauri.weiv.bundle.conf.json --no-sign`, launch the preview, and open an untracked two-line text file from Changes. A Chrome fixture at `tests/browser/weiv-timeline-search.html` is the comparison.
- **Expected:** each diff row appears at its projected vertical offset in both Chrome and packaged WKWebView.
- **Actual:** Chrome showed separate lines; the packaged app painted all diff text on top of itself at the first row. No JavaScript error was observed. The first native screenshot was taken after the diff loaded, and the app's Git status and target file were correct.
- **Workaround:** remove per-row absolute positioning and render the bounded row window in normal flow, with a single projected `padding-top` offset on its wrapper and a total-height sizer. Rebuilding the app displayed the header, hunk, two green additions, and line numbers on separate rows. This is a confirmed project integration workaround; root cause remains open.

The same imported-binding initialization defect recurred while adding the Weiv terminal dock. `App.weiv` declared `let terminalOpen = useTerminalStore.getState().open;` at component setup, with `useTerminalStore` imported from `@/features/terminal/store`. `corepack pnpm build` succeeded, but the Chrome fixture failed to mount with `ReferenceError: Cannot access 'useTerminalStore' before initialization` at generated `setup()` line 1391. Expected: the imported store is initialized before the setup expression. Moving the store read and `WeivTerminalController` construction into the existing `queueMicrotask` initialization restored mounting; the packaged macOS preview then opened a PTY and displayed shell output. Environment: `weivjs@0.1.1`, local Weiv checkout `1633af0`, macOS arm64, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3. This is a recurrence of the confirmed compiler defect above, not a new issue.

## Packaged terminal context menu ignored bound position

- **Classification:** production Weiv/WKWebView style-binding interoperability gap; root cause unconfirmed.
- **Context:** CC GUI Weiv terminal dock, `weivjs@0.1.1` (local checkout `1633af0`), macOS arm64, Tauri packaged WKWebView, Node 22.22.1, pnpm 10.29.3, Vite 6.4.3.
- **Reproduce:** select text in the xterm dock, right-click near the middle of the dock, render `<div class="weiv-terminal-menu" :style="props.view.menu.style">` with `position:fixed` CSS and a projected `left:${x}px;top:${y}px` string from the pointer event. Build with `corepack pnpm exec tauri build --debug --bundles app --config src-tauri/tauri.weiv.bundle.conf.json --no-sign` and launch the preview.
- **Expected:** the menu appears by the pointer, clamped to the viewport.
- **Actual:** the packaged menu appeared at the terminal dock's left edge regardless of the projected position. No runtime error appeared; right-click selection and menu entries worked. The screenshot showed the click around x=700 and menu starting at the main pane's x=520. A browser comparison was not performed for this exact binding.
- **Workaround:** after Weiv renders the menu, set the menu element's `style.left` and `style.top` directly from the saved pointer coordinates, including after view refreshes. The next native build placed the menu beside the pointer. A final packaged build verified that focusing the menu allows Escape to close it.
