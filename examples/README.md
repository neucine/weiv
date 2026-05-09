# Weiv Examples

These examples are the canonical Phase 0 authoring references for `weiv`.

They exist to validate the locked syntax and give Phase 1 compiler work a stable fixture set.

## Example Set

- [Basic Counter](./basic-counter.weiv)
- [Todo List](./todo-list.weiv)
- [Dashboard Card](./dashboard-card.weiv)
- [Metric Badge](./MetricBadge.weiv)
- [Classic Todo App](./classic-todo/README.md)
- [TodoMVC Verification App](./todomvc/README.md)

## Coverage

Together, these examples exercise:

- props
- local mutable state
- helper functions
- event binding
- conditional rendering
- list rendering
- child component composition
- scoped styles
- larger multi-component app verification

## Notes

- `examples/todomvc` is the primary smaller app-scale verification example.
- The smaller fixtures remain useful for narrow compiler regressions.
- The repo still needs a clearly larger flagship verification app above
  TodoMVC.
