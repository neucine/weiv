# Weiv MVP Checklist

## Purpose

This checklist defines the minimum product surface required before `weiv` can claim an MVP preview.

Anything not listed here is deferred unless it is required to make one of these items work.

## Core Authoring

- `.weiv` single-file components compile successfully
- `<template>` is supported
- `<script lang="ts">` is supported
- `<style>` is supported
- props are supported through `export let props: Props`
- ordinary local mutable state works
- ordinary helper functions can be referenced from templates

## Template Features

- text interpolation works
- event binding with `on:` works
- dynamic attribute binding with `bind:` works for the supported MVP set
- `if` works
- `else` works
- `for="item in items"` works
- child component composition works

## Compiler

- SFC parsing exists
- template parsing exists
- script analysis exists
- template-to-script symbol binding exists
- unresolved symbol diagnostics exist
- scoped CSS transform exists
- compiler IR exists
- JS emission exists
- CSS emission exists
- sourcemaps exist

## Runtime

- components mount in the browser
- props initialize correctly
- text updates render after local state mutation
- conditionals update correctly
- lists update correctly
- event listeners attach and clean up correctly
- child components mount and unmount correctly
- destroy lifecycle path exists internally

## CLI And Tooling

- `weiv build` exists
- `weiv watch` exists, even if simple
- emitted JS/CSS can be consumed by Bun workflows
- compiler diagnostics print clearly in CLI output
- generated artifacts are inspectable during development

## TypeScript And DX

- prop types are preserved through the authoring flow
- template symbol errors point back to `.weiv` source locations
- common authoring mistakes produce actionable diagnostics
- stack traces and source locations are usable enough for local debugging

## Validation Examples

- one toy example exists
- one realistic example exists
- the realistic example uses:
  - nested components
  - lists
  - conditionals
  - events
  - derived display values
  - scoped styles

## Explicit Non-MVP

- SSR
- hydration
- router
- transitions system
- forms package
- data cache/resource framework
- public advanced reactivity primitives as the default model
- dev server owned by `weiv`

## MVP Exit Rule

`weiv` reaches MVP preview readiness only when every required item above is implemented and the realistic example can be built without introducing off-spec escape hatches.
