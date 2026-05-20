---
layout: home

hero:
  name: ""
  text: "Frontend, with room to breathe."
  tagline: "A compiler-first UI framework for single-file components, direct DOM updates, and a tiny optional runtime."
  image:
    src: /assets/weiv.png
    alt: Weiv
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: Read the Architecture
      link: /architecture

features:
  - title: Compiler-First
    details: Keep authoring in `.weiv` single-file components and let compilation own the heavy lifting.
  - title: Direct DOM
    details: Emit targeted DOM programs instead of carrying a framework-wide VDOM layer at runtime.
  - title: TypeScript Without JSX
    details: Keep template, script, and style separate while staying friendly to normal TypeScript authoring.
  - title: Small Runtime Surface
    details: Use no runtime by default, then opt into focused helpers for observables and routing when needed.
---

# Why Weiv

Weiv is building toward a frontend model that stays simple at the authoring
surface while pushing more precision into compile time.

Start with [Getting Started](./getting-started.md) for installation and CLI
usage, then move on to [Simple Component](./simple-component.md),
[Shared State](./shared-state.md), [VS Code Extension](./vscode-extension.md),
[Router Example](./router-example.md), [Architecture](./architecture.md), and
[Runtime API](./runtime-api.md) as you go deeper.
