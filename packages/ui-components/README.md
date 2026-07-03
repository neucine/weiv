# @weivjs/ui-components

Weiv-first UI components built on internal headless contracts.

## Public Components (Phase 1)

- `WuiDialog`
- `WuiDisclosure`
- `WuiTabs`

## Usage (workspace/local)

```ts
import WuiDialog from "@weivjs/ui-components/WuiDialog.weiv";
import WuiDisclosure from "@weivjs/ui-components/WuiDisclosure.weiv";
import WuiTabs from "@weivjs/ui-components/WuiTabs.weiv";
```

Also include theme styles:

```ts
import "@weivjs/ui-theme-default/tokens.css";
import "@weivjs/ui-theme-default/components.css";
```

## Note

`@weivjs/ui-core` controllers are internal implementation details of these
components and are not intended as the primary consumer-facing API.
