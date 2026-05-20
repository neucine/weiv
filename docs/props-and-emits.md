# Props And Emits

Use props to pass data into a component, and use emits to send events back out.

## Read Props

Props are available through the `props` object inside the component script and
template.

```html
<template>
  <section class="card">
    <h2>{{ props.title }}</h2>
    <p>{{ props.description }}</p>
  </section>
</template>
```

This is the usual shape for read-only input coming from a parent component.

## Pass Props From A Parent

Use `bind:` to pass expressions into child component props.

```html
<template>
  <DashboardCard
    bind:title="'Release Notes'"
    bind:description="summary"
  />
</template>

<script lang="ts">
  let summary = "Compiler and docs updates for this sprint.";
</script>
```

`bind:` works for literals, local state, and derived values.

## Use Props In Logic

Props can drive conditionals, derived classes, and small helper functions.

```html
<template>
  <button bind:disabled="count >= limit">
    Add
  </button>
</template>

<script lang="ts">
  let count = props.initialCount ?? 0;
  let limit = props.limit ?? 5;
</script>
```

## Emit Events

Use `emit(name, payload)` when a child component needs to notify its parent.

```html
<template>
  <button on:click="handleOpen">Open</button>
</template>

<script lang="ts">
  function handleOpen() {
    emit("open", props.id);
  }
</script>
```

This keeps upward communication explicit instead of mutating parent state
directly.

## Listen To Child Events

Use `on:event` on the child component in the parent template.

```html
<template>
  <IssueCard
    bind:id="issue.id"
    bind:title="issue.title"
    on:open="selectIssue"
  />
</template>

<script lang="ts">
  function selectIssue(issueId) {
    console.log("Open issue", issueId);
  }
</script>
```

## Common Pattern

Props in, emits out is a good default when:

- a parent owns the data
- a child renders or edits part of that data
- the child needs to signal actions like `save`, `open`, `toggle`, or `remove`

## Example

```html
<template>
  <TodoItem
    bind:todo="todo"
    bind:editing="editingId === todo.id"
    on:toggle="handleToggle"
    on:destroy="handleDestroy"
    on:save-edit="handleSaveEdit"
  />
</template>
```

That pattern keeps data flow easy to follow:

- parent passes state down through props
- child emits named actions upward
- parent decides how shared or app-level state changes

## Next Step

Use [Template Syntax](./template-syntax.md) for `bind:` and `on:` syntax, or
[Reactivity](./reactivity.md) for the local-state model inside a component.
