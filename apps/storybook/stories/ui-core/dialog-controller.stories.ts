import * as DialogBasic from "./DialogBasic.weiv";

export default {
  title: "UI Core/Dialog Controller",
};

const usageCode = `<template>
  <wui-dialog bind:data-state="open ? 'open' : 'closed'">
    <wui-dialog-trigger>
      <button class="wv-button" on:click="openDialog">Open dialog</button>
    </wui-dialog-trigger>

    <wui-dialog-overlay bind:hidden="!open" on:click="onBackdropClick">
      <wui-dialog-content on:click="stopBubbling">
        <wui-dialog-title>Dialog preview</wui-dialog-title>
        <wui-dialog-description class="wv-help">
          Example consumer usage with outside-click close.
        </wui-dialog-description>
        <wui-dialog-footer>
          <button class="wv-button" on:click="closeDialog">Confirm</button>
          <button class="wv-button story-cancel" on:click="closeDialog">Cancel</button>
        </wui-dialog-footer>
      </wui-dialog-content>
    </wui-dialog-overlay>
  </wui-dialog>
</template>

<script lang="ts">
  let open = false;

  function openDialog() {
    open = true;
  }

  function closeDialog() {
    open = false;
  }

  function onBackdropClick() {
    closeDialog();
  }

  function stopBubbling(event: MouseEvent) {
    event.stopPropagation();
  }
</script>`;

export const BasicOpenClose = () => {
  const root = document.createElement("div");
  DialogBasic.mount(root);
  return root;
};

BasicOpenClose.parameters = {
  docs: {
    description: {
      story:
        "Showcases trigger open, overlay outside-click close, and action-button close. Source below matches the rendered .weiv usage.",
    },
    source: {
      code: usageCode,
      language: "html",
    },
  },
};

export const UsageCode = () => {
  const pre = document.createElement("pre");
  pre.style.whiteSpace = "pre-wrap";
  pre.style.background = "var(--weiv-color-surface)";
  pre.style.border = "1px solid var(--weiv-color-border)";
  pre.style.borderRadius = "var(--weiv-radius-md)";
  pre.style.padding = "16px";
  pre.style.font = "13px/1.45 var(--weiv-font-mono)";
  pre.textContent = usageCode;
  return pre;
};

UsageCode.parameters = {
  docs: {
    source: {
      code: usageCode,
      language: "html",
    },
  },
};
