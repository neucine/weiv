---
layout: home

hero:
  name: ""
  text: "Frontend, with room to breathe."
  tagline: "A compiler-first UI framework for single-file components, direct DOM updates, and a near-zero optional runtime."
  image:
    src: /assets/weiv.png
    alt: Weiv
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: Read the Docs
      link: /architecture

features:
  - title: Compiler-First
    details: Keep authoring in `.weiv` single-file components and let compilation own the heavy lifting.
  - title: Direct DOM
    details: Emit targeted DOM programs instead of carrying a framework-wide VDOM layer at runtime.
  - title: Reactivity Without Ceremony
    details: Keep local state effortless and close to the component, without extra wiring or framework ceremony. Reach for explicit shared state only when truly needed.
  - title: Near-Zero Runtime
    details: Keep runtime cost close to zero by default. Add the helper layer only for features that benefit from it, such as observables or routing.
---

# Why Weiv

Weiv is building toward a frontend model that stays simple at the authoring
surface while pushing more precision into compile time.

Start with [Getting Started](./getting-started.md) for installation and CLI
usage, then move on to [Simple Component](./simple-component.md),
[Shared State](./shared-state.md), [VS Code Extension](./vscode-extension.md),
[Router Example](./router-example.md), [Architecture](./architecture.md), and
[Runtime API](./runtime-api.md) as you go deeper.
