# Weiv Public Docs

This directory is now the public documentation source for Weiv.

Public docs kept here:

- [Site Home](./index.md)
- [Getting Started](./getting-started.md)
- [Framework Vision](./framework-vision.md)
- [Architecture](./architecture.md)
- [Runtime Scheduling](./runtime-scheduling.md)
- [Runtime API](./runtime-api.md)
- [Terminology](./terminology.md)
- [Status](./status.md)
- [NPM Single-Package Distribution](./npm-single-package-distribution.md)
- [UI Library Direction](./ui-library-direction.md)
- [UI Library Spec](./ui-library-spec.md)

Internal design, planning, testing, and execution docs now live in the sibling
`../weiv-arch` repo.

Publishing happens from the sibling `../weiv.dev` repo, which owns the static
site build and Cloudflare deploy config.

If you update public docs here, sync them into `weiv.dev` before publishing.

Current publish flow:

```bash
cd ../weiv.dev
./scripts/sync-from-weiv.sh
npm install
npm run build
```
