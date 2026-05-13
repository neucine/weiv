# VS Code Extension Publish

The VS Code extension lives at:

- `packages/vscode-extension`

## Prerequisites

1. Marketplace publisher is configured in `packages/vscode-extension/package.json`.
2. You have a Visual Studio Marketplace Personal Access Token (PAT).
3. Export token in shell:

```bash
export VSCE_PAT=your_marketplace_pat
```

## Package Only (Dry Run)

From repo root:

```bash
npm run vscode:package
```

This builds the extension and generates a `.vsix` package.

## Publish

From repo root:

```bash
npm run vscode:publish
```

This builds, packages, and publishes via `vsce`.

## Direct Script Usage

```bash
tools/publish-vscode.sh --dry-run
tools/publish-vscode.sh --publish
```
