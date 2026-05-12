# Weiv for VS Code

Syntax highlighting for `.weiv` single-file components.

## Features

- Language registration for `.weiv` files
- Embedded language support:
  - HTML in `<template>`
  - TypeScript in `<script lang="ts">`
  - CSS in `<style>`
- Weiv-specific highlighting:
  - `bind:prop` directive bindings
  - `on:event` event handlers
  - `if` / `else` / `for` control flow attributes
  - `slot` directives
  - `{{ expression }}` template interpolation
  - PascalCase component tags (distinct from HTML tags)
- Bracket matching, auto-closing, and folding for section blocks

## Install (development)

```bash
cd editors/vscode
npx @vscode/vsce package
code --install-extension weiv-vscode-0.1.0.vsix
```

Or open this folder in VS Code and press F5 to launch an Extension Development Host.
