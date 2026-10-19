# Weiv integration friction

This report records friction found while building the interactive Roam, Muse,
and Hearth demos with Weiv. It is prepared as product feedback; no external
issue has been submitted.

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
