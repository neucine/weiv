# Weiv integration friction

This report records friction found while building the interactive Roam demo in
`apps/roam` with Weiv. It is prepared as product feedback; no external issue has
been submitted.

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

| Finding | Classification | Impact | Workaround used |
| --- | --- | --- | --- |
| `if` nested in `for` uses the wrong ref scope | Confirmed code-generation/runtime defect | Later list entries and following UI can disappear | Replace the conditional node with text/class bindings |
| State assigned after `await` does not refresh immediately | Async boundary limitation or documentation gap | Server changes succeed but the visible UI remains stale | Apply post-`await` changes inside `queueMicrotask` |
| `bind:value` is not two-way input binding | API naming/documentation gap | Forms submit stale component state | Add an explicit `on:input` handler |
| `:global(...)` is emitted as scoped CSS | Missing capability or compiler defect | Root variables and body styles do not apply | Scope variables to the app and put shell CSS in the host page |
| Full-app emit/package-runner builds were killed | Tooling/resource interoperability issue | Normal package scripts could not reliably build this component | Invoke split JS/CSS compilation with the direct shell script |
| Successful validation prints allocator leak errors | Confirmed tooling defect | Clean CI output is impossible and a real leak may be hidden | None; command still exits zero |

## 1. Conditional nodes inside loops lose loop-local scope

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
