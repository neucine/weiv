# Weiv Examples

These examples are the current authoring and verification fixtures for `weiv`.

They are not all equal:

- some are human-facing reference examples
- some are focused compiler/runtime fixtures
- some are negative fixtures used to prove diagnostics or unsupported cases

## Reference Examples

Good small examples to read first:

- [Basic Counter](./basic/basic-counter.weiv)
- [Todo List](./basic/todo-list.weiv)
- [Dashboard Card](./basic/dashboard-card.weiv)
- [Metric Badge](./basic/MetricBadge.weiv)
- [Conditional Toggle](./basic/conditional-toggle.weiv)

## App-Scale Verification

Multi-component verification examples:

- [Workspace App](./workspace-app/README.md)
- [Classic Todo App](./classic-todo/README.md)
- [TodoMVC Verification App](./todomvc/README.md)

Current role:

- `test/examples/workspace-app` is the larger flagship verification app scaffold
- `test/examples/todomvc` is the main smaller app-scale verification example
- `test/examples/classic-todo` is still useful as a simpler multi-component app

## Focused Runtime / Compiler Fixtures

These exist mainly to pressure-test specific behaviors:

- [Timer Callback](./basic/timer-callback.weiv): owned callback scheduling
- [Imported Helper](./imported-helper/App.weiv): runtime JS import copying
- [Imported TS Helper](./imported-ts-helper/App.weiv): TS helper transpile +
  import rewriting

## Slot / Projection Fixtures

The `slots/` directory is a focused fixture set for:

- default slots
- named slots
- fallback content
- grouped slot templates
- projected updates
- nested slot trees

Useful entry points:

- [Panel](./slots/Panel.weiv)
- [Panel Usage](./slots/PanelUsage.weiv)
- [Card](./slots/Card.weiv)
- [Slot Showcase](./slots/SlotShowcase.weiv)

## Negative Fixture

- `unsupported-import/`

This is an intentional failure case used to verify unsupported bare runtime
import diagnostics.
