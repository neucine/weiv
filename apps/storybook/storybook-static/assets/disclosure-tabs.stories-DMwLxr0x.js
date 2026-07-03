import{i as e}from"./preload-helper-Cs4UwXAW.js";function t(e=`weiv`){let t=(a.get(e)??0)+1;return a.set(e,t),`${e}-${t}`}function n(e){let t=e,n=new Set;function r(){for(let e of n)e(t)}return{get value(){return t},set(e){Object.is(t,e)||(t=e,r())},subscribe(e){return n.add(e),e(t),()=>n.delete(e)}}}function r({initialExpanded:e=!1}={}){let r=n(!!e),i=t(`wv-disclosure-content`);return{get expanded(){return r.value},get contentId(){return i},expand(){r.set(!0)},collapse(){r.set(!1)},toggle(){r.set(!r.value)},getTriggerA11yProps({controls:e=i}={}){return{"aria-expanded":r.value?`true`:`false`,"aria-controls":e}},getContentA11yProps({id:e=i}={}){return{id:e,hidden:r.value?void 0:!0}},subscribe(e){return r.subscribe(e)}}}function i({tabs:e=[],initialValue:r,activationMode:i=`automatic`,orientation:a=`horizontal`}={}){let o=e.map(e=>typeof e==`string`?{value:e,disabled:!1}:{disabled:!1,...e}),s=o.find(e=>!e.disabled)?.value??null,c=r??s,l=n(c),u=n(c),d=t(`wv-tabs-list`);function f(){return o.map(e=>e.value)}function p(e){return o.find(t=>t.value===e)?.disabled??!0}function m(e){let t=f().filter(e=>!p(e));if(t.length===0)return;let n=u.value,r=t[(Math.max(t.indexOf(n),0)+e+t.length)%t.length];u.set(r),i===`automatic`&&l.set(r)}return{get selectedValue(){return l.value},get focusedValue(){return u.value},get tablistId(){return d},get tabs(){return o.slice()},select(e){p(e)||(l.set(e),u.set(e))},focus(e){p(e)||(u.set(e),i===`automatic`&&l.set(e))},onTabKeydown(e){let t=a===`horizontal`,n=e.key;if(t&&n===`ArrowRight`||!t&&n===`ArrowDown`)return e.preventDefault?.(),m(1),!0;if(t&&n===`ArrowLeft`||!t&&n===`ArrowUp`)return e.preventDefault?.(),m(-1),!0;if(n===`Home`){e.preventDefault?.();let t=o.find(e=>!e.disabled)?.value;return t!=null&&(u.set(t),i===`automatic`&&l.set(t)),!0}if(n===`End`){e.preventDefault?.();let t=o.filter(e=>!e.disabled),n=t[t.length-1]?.value;return n!=null&&(u.set(n),i===`automatic`&&l.set(n)),!0}return(n===`Enter`||n===` `)&&i===`manual`&&u.value!=null?(e.preventDefault?.(),l.set(u.value),!0):!1},getTablistA11yProps(){return{id:d,role:`tablist`,"aria-orientation":a}},getTabA11yProps(e){let t=l.value===e;return{role:`tab`,"aria-selected":t?`true`:`false`,"aria-controls":`${d}-panel-${e}`,id:`${d}-tab-${e}`,tabIndex:u.value===e?0:-1,"data-state":t?`active`:`inactive`,"data-disabled":p(e)?`true`:void 0}},getPanelA11yProps(e){let t=l.value===e;return{role:`tabpanel`,id:`${d}-panel-${e}`,"aria-labelledby":`${d}-tab-${e}`,hidden:t?void 0:!0}},subscribe(e){let t=()=>{e({selectedValue:l.value,focusedValue:u.value})},n=[l.subscribe(t),u.subscribe(t)];return()=>{for(let e of n)e()}}}}var a,o=e((()=>{a=new Map})),s,c,l,u;e((()=>{o(),s={title:`UI Core/Disclosure + Tabs`},c=()=>{let e=r(),t=document.createElement(`div`);t.style.display=`grid`,t.style.gap=`12px`,t.style.maxWidth=`560px`;let n=document.createElement(`button`);n.className=`wv-button`,n.textContent=`Toggle details`;let i=document.createElement(`div`);return i.style.background=`var(--weiv-color-surface)`,i.style.border=`1px solid var(--weiv-color-border)`,i.style.borderRadius=`var(--weiv-radius-md)`,i.style.padding=`12px`,i.textContent=`Panel content: release notes and rollout checklist.`,n.addEventListener(`click`,()=>e.toggle()),e.subscribe(()=>{let t=e.getTriggerA11yProps();n.setAttribute(`aria-expanded`,t[`aria-expanded`]),n.setAttribute(`aria-controls`,t[`aria-controls`]);let r=e.getContentA11yProps();i.id=r.id,i.hidden=!!r.hidden}),t.append(n,i),t},c.parameters={docs:{source:{code:`import { createDisclosureController } from "@weivjs/ui-core";

const disclosure = createDisclosureController();
trigger.addEventListener("click", () => disclosure.toggle());

disclosure.subscribe(() => {
  const triggerProps = disclosure.getTriggerA11yProps();
  const contentProps = disclosure.getContentA11yProps();
});`}}},l=()=>{let e=i({tabs:[`Overview`,`Activity`,`Settings`],initialValue:`Overview`,activationMode:`automatic`}),t=document.createElement(`div`);t.style.display=`grid`,t.style.gap=`12px`,t.style.maxWidth=`680px`;let n=document.createElement(`div`);n.style.display=`flex`,n.style.gap=`8px`;let r=document.createElement(`section`);r.style.background=`var(--weiv-color-surface)`,r.style.border=`1px solid var(--weiv-color-border)`,r.style.borderRadius=`var(--weiv-radius-md)`,r.style.padding=`14px`;let a=e.tabs.map(e=>e.value);for(let t of a){let r=document.createElement(`button`);r.className=`wv-button`,r.style.minWidth=`120px`,r.textContent=t,r.addEventListener(`click`,()=>e.select(t)),r.addEventListener(`keydown`,t=>{if(!e.onTabKeydown(t))return;let r=e.focusedValue,i=n.querySelector(`[data-tab-value="${r}"]`);i instanceof HTMLButtonElement&&i.focus(),o()}),r.dataset.tabValue=t,n.appendChild(r)}let o=()=>{let t=e.getTablistA11yProps();n.setAttribute(`role`,t.role),n.setAttribute(`aria-orientation`,t[`aria-orientation`]);for(let t of Array.from(n.children)){if(!(t instanceof HTMLButtonElement))continue;let n=t.dataset.tabValue;if(!n)continue;let r=e.getTabA11yProps(n);t.setAttribute(`role`,r.role),t.setAttribute(`aria-selected`,r[`aria-selected`]),t.setAttribute(`aria-controls`,r[`aria-controls`]),t.id=r.id,t.tabIndex=r.tabIndex,t.dataset.state=r[`data-state`],t.style.opacity=r[`data-state`]===`active`?`1`:`0.72`}r.textContent=`Current tab: ${e.selectedValue}`};return e.subscribe(o),t.append(n,r),t},l.parameters={docs:{source:{code:`import { createTabsController } from "@weivjs/ui-core";

const tabs = createTabsController({
  tabs: ["Overview", "Activity", "Settings"],
  activationMode: "automatic",
});

button.addEventListener("keydown", (event) => {
  tabs.onTabKeydown(event);
});`}}},c.parameters={...c.parameters,docs:{...c.parameters?.docs,source:{originalSource:`() => {
  const disclosure = createDisclosureController();
  const root = document.createElement("div");
  root.style.display = "grid";
  root.style.gap = "12px";
  root.style.maxWidth = "560px";
  const trigger = document.createElement("button");
  trigger.className = "wv-button";
  trigger.textContent = "Toggle details";
  const panel = document.createElement("div");
  panel.style.background = "var(--weiv-color-surface)";
  panel.style.border = "1px solid var(--weiv-color-border)";
  panel.style.borderRadius = "var(--weiv-radius-md)";
  panel.style.padding = "12px";
  panel.textContent = "Panel content: release notes and rollout checklist.";
  const sync = () => {
    const triggerProps = disclosure.getTriggerA11yProps();
    trigger.setAttribute("aria-expanded", triggerProps["aria-expanded"]);
    trigger.setAttribute("aria-controls", triggerProps["aria-controls"]);
    const contentProps = disclosure.getContentA11yProps();
    panel.id = contentProps.id;
    panel.hidden = Boolean(contentProps.hidden);
  };
  trigger.addEventListener("click", () => disclosure.toggle());
  disclosure.subscribe(sync);
  root.append(trigger, panel);
  return root;
}`,...c.parameters?.docs?.source}}},l.parameters={...l.parameters,docs:{...l.parameters?.docs,source:{originalSource:`() => {
  const tabs = createTabsController({
    tabs: ["Overview", "Activity", "Settings"],
    initialValue: "Overview",
    activationMode: "automatic"
  });
  const root = document.createElement("div");
  root.style.display = "grid";
  root.style.gap = "12px";
  root.style.maxWidth = "680px";
  const tablist = document.createElement("div");
  tablist.style.display = "flex";
  tablist.style.gap = "8px";
  const panel = document.createElement("section");
  panel.style.background = "var(--weiv-color-surface)";
  panel.style.border = "1px solid var(--weiv-color-border)";
  panel.style.borderRadius = "var(--weiv-radius-md)";
  panel.style.padding = "14px";
  const labels = tabs.tabs.map(tab => tab.value);
  for (const label of labels) {
    const button = document.createElement("button");
    button.className = "wv-button";
    button.style.minWidth = "120px";
    button.textContent = label;
    button.addEventListener("click", () => tabs.select(label));
    button.addEventListener("keydown", event => {
      const handled = tabs.onTabKeydown(event);
      if (!handled) return;
      const focused = tabs.focusedValue;
      const target = tablist.querySelector(\`[data-tab-value="\${focused}"]\`);
      if (target instanceof HTMLButtonElement) target.focus();
      sync();
    });
    button.dataset.tabValue = label;
    tablist.appendChild(button);
  }
  const sync = () => {
    const tablistProps = tabs.getTablistA11yProps();
    tablist.setAttribute("role", tablistProps.role);
    tablist.setAttribute("aria-orientation", tablistProps["aria-orientation"]);
    for (const child of Array.from(tablist.children)) {
      if (!(child instanceof HTMLButtonElement)) continue;
      const value = child.dataset.tabValue;
      if (!value) continue;
      const props = tabs.getTabA11yProps(value);
      child.setAttribute("role", props.role);
      child.setAttribute("aria-selected", props["aria-selected"]);
      child.setAttribute("aria-controls", props["aria-controls"]);
      child.id = props.id;
      child.tabIndex = props.tabIndex;
      child.dataset.state = props["data-state"];
      child.style.opacity = props["data-state"] === "active" ? "1" : "0.72";
    }
    panel.textContent = \`Current tab: \${tabs.selectedValue}\`;
  };
  tabs.subscribe(sync);
  root.append(tablist, panel);
  return root;
}`,...l.parameters?.docs?.source}}},u=[`DisclosureBasics`,`TabsBasics`]}))();export{c as DisclosureBasics,l as TabsBasics,u as __namedExportsOrder,s as default};