# @weivjs/ui-core

Headless UI primitives for Weiv.

## Purpose

`@weivjs/ui-core` provides behavior and accessibility-first utilities without
forcing visual style.

Use this package when you want strict interaction contracts and theme your own
components.

## Current Surface (Starter)

- `createDialogController` - open/close state and listeners
- `createDisclosureController` - expand/collapse state and listeners
- `createControllableState` - controlled/uncontrolled state helper
- `createId` - predictable ID generator

## Install

```bash
npm i @weivjs/ui-core
```

## Example

```js
import { createDialogController } from "@weivjs/ui-core";

const dialog = createDialogController();
dialog.subscribe((open) => {
  console.log("dialog open:", open);
});

dialog.open();
```
