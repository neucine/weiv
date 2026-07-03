import{i as e}from"./preload-helper-Cs4UwXAW.js";function t(e,t,n){let r=e.parentNode;if(!r||r!==t.parentNode)throw Error(`Conditional boundary is detached`);let i=e.nextSibling;for(;i&&i!==t;){let e=i.nextSibling;r.removeChild(i),i=e}r.insertBefore(n,t)}function n(e){let t={};for(let n of Object.keys(e))t[n]=e[n];return t}function r(e,t){let n=[],r=new Set;for(let i of Object.keys(e))r.add(i),(!Object.prototype.hasOwnProperty.call(t,i)||!Object.is(e[i],t[i]))&&n.push(i);for(let i of Object.keys(t))r.has(i)||Object.prototype.hasOwnProperty.call(e,i)||n.push(i);return n}function i(e){return Array.isArray(e)?{bindings:e,paths:[]}:!e||typeof e!=`object`?{bindings:[],paths:[]}:{bindings:Array.isArray(e.bindings)?e.bindings:[],paths:Array.isArray(e.paths)?e.paths:[]}}function a(){if(C.size===0)return[];let e=Array.from(C);return C.clear(),e}function o(){return w&&Array.isArray(w.roots)&&w.roots.length>0}function s(e){o()&&S.add(e)}function c(e){S.delete(e)}function l(e,t){if(e.destroyed)return t;let i=e.refresh(),o=r(t,i),s=a();return o.length>0||s.length>0?(typeof e.updateDirty==`function`?e.updateDirty({bindings:o,paths:s},i):e.update(),n(e.refresh())):n(i)}function u(e,t){let r=n(e.refresh()),i;try{i=t()}catch(t){throw l(e,r),t}return r=l(e,r),i&&typeof i.then==`function`?i.finally(()=>{l(e,r)}):i}function d(e,t={}){let n=e,r=t,i=(e,t)=>{if(typeof r[e]==`function`)return r[e](t)},a=!1;function o(){a=!0}function s(){a=!1}function c(){s()}function l(e){e.stopPropagation()}let u={};function d(){return u.props=n,u.emit=i,u.open=a,u.openDialog=o,u.closeDialog=s,u.onBackdropClick=c,u.stopBubbling=l,u}function f(e){n=e}function p(e){r=e}function m(e){}function h(e){let t=[];return()=>{for(let e of t)e()}}return{scope:u,refresh:d,setProps:f,setEventHandlers:p,setBoundaryRunner:m,subscribeImportedObservables:h}}function f(e){let t=document.createDocumentFragment(),n=e.refs,r=document.createElement(`section`);n[12]=r,r.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),r.setAttribute(`class`,`story-root`);let i=document.createElement(`wui-dialog`);n[11]=i,i.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`);let a=document.createElement(`wui-dialog-trigger`);n[1]=a,a.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`);let o=document.createElement(`button`);n[0]=o,o.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),o.setAttribute(`class`,`wv-button`),o.addEventListener(`click`,t=>{let n=e.refresh().openDialog;if(typeof n==`function`)return u(e,()=>n(t))}),o.append(document.createTextNode(`Open dialog`)),a.append(o),i.append(a);let s=document.createElement(`p`);n[3]=s,s.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),s.setAttribute(`class`,`wv-help`),s.append(document.createTextNode(`State: `));let c=document.createTextNode(``);n[2]=c,s.append(c),i.append(s);let l=document.createElement(`wui-dialog-overlay`);n[10]=l,l.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),l.setAttribute(`class`,`dialog-overlay`),l.addEventListener(`click`,t=>{let n=e.refresh().onBackdropClick;if(typeof n==`function`)return u(e,()=>n(t))});let d=document.createElement(`wui-dialog-content`);n[9]=d,d.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),d.setAttribute(`class`,`dialog-content`),d.addEventListener(`click`,t=>{let n=e.refresh().stopBubbling;if(typeof n==`function`)return u(e,()=>n(t))});let f=document.createElement(`wui-dialog-title`);n[4]=f,f.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),f.setAttribute(`class`,`dialog-title`),f.append(document.createTextNode(`Dialog preview`)),d.append(f);let p=document.createElement(`wui-dialog-description`);n[5]=p,p.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),p.setAttribute(`class`,`wv-help`),p.append(document.createTextNode(`
          This canvas now uses the same wui-dialog API shape.
        `)),d.append(p);let m=document.createElement(`wui-dialog-footer`);n[8]=m,m.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),m.setAttribute(`class`,`dialog-footer`);let h=document.createElement(`button`);n[6]=h,h.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),h.setAttribute(`class`,`wv-button`),h.addEventListener(`click`,t=>{let n=e.refresh().closeDialog;if(typeof n==`function`)return u(e,()=>n(t))}),h.append(document.createTextNode(`Confirm`)),m.append(h);let g=document.createElement(`button`);return n[7]=g,g.setAttribute(`data-weiv-scope`,`w211F315A76E36F26`),g.setAttribute(`class`,`wv-button story-cancel`),g.addEventListener(`click`,t=>{let n=e.refresh().closeDialog;if(typeof n==`function`)return u(e,()=>n(t))}),g.append(document.createTextNode(`Cancel`)),m.append(g),d.append(m),l.append(d),i.append(l),r.append(i),t.append(r),t}function p(e,t,n){let r=t.open?`open`:`closed`;r===!1||r==null?n[11].hasAttribute(`data-state`)&&n[11].removeAttribute(`data-state`):r===!0?n[11].hasAttribute(`data-state`)||n[11].setAttribute(`data-state`,``):n[11].setAttribute(`data-state`,String(r))}function m(e,t,n){let r=String(t.open?`open`:`closed`);n[2].data!==r&&(n[2].data=r)}function h(e,t,n){let r=t.open?`display:grid`:`display:none`;r===!1||r==null?n[10].hasAttribute(`style`)&&n[10].removeAttribute(`style`):r===!0?n[10].hasAttribute(`style`)||n[10].setAttribute(`style`,``):n[10].setAttribute(`style`,String(r))}function g(e){let t=e.refs,n=e.refresh();p(e,n,t),m(e,n,t),h(e,n,t)}function _(e,t,n=e.refresh()){let r=e.refs,a=i(t),o=new Set(a.bindings),s=new Set(a.paths),c=new Set;if(s.size>0&&w&&Array.isArray(w.regions)){for(let e of w.regions)if(!(!e||!Array.isArray(e.trackedPathIds))){for(let t of e.trackedPathIds)if(s.has(t)){c.add(e.regionId);break}}}(o.has(`open`)||c.has(1))&&p(e,n,r),(o.has(`open`)||c.has(2))&&m(e,n,r),(o.has(`open`)||c.has(3))&&h(e,n,r)}function v(e){e.refs}function y(e={},t={},n={}){let r=d(e,t),i={scope:r.scope,refresh:r.refresh,setProps:r.setProps,setEventHandlers:r.setEventHandlers,setBoundaryRunner:r.setBoundaryRunner,subscribeImportedObservables:r.subscribeImportedObservables,slots:n,setSlots:(e={})=>{i.slots=e},refs:[],destroyed:!1,update:()=>{},updateDirty:()=>{},destroy:()=>{}};return i.setBoundaryRunner(e=>u(i,e)),s(i),i}function b(e,n,r={},i={},a={}){let o=y(r,i,a);o.setSlots=(e={})=>{o.slots=e},t(e,n,f(o)),o.update=()=>g(o),o.updateDirty=(e,t)=>_(o,e,t);let s=typeof o.subscribeImportedObservables==`function`?o.subscribeImportedObservables(o):null;return o.destroy=()=>{typeof s==`function`&&s(),c(o),o.destroyed=!0,v(o),t(e,n,document.createDocumentFragment())},o.update(),{instance:o,update:o.update,destroy:o.destroy,setProps:o.setProps,setEventHandlers:o.setEventHandlers,setSlots:o.setSlots,start:e,end:n}}function x(e,t={},n={},r={}){let i=document.createComment(`root:start`),a=document.createComment(`root:end`);return e.replaceChildren(i,a),b(i,a,t,n,r)}var S,C,w,T=e((()=>{S=new Set,C=new Set,w={roots:[],paths:[],regions:[]}})),E,D,O,k,A;e((()=>{T(),E={title:`UI Core/Dialog Controller`},D=`<template>
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
<\/script>`,O=()=>{let e=document.createElement(`div`);return x(e),e},O.parameters={docs:{description:{story:`Showcases trigger open, overlay outside-click close, and action-button close. Source below matches the rendered .weiv usage.`},source:{code:D,language:`html`}}},k=()=>{let e=document.createElement(`pre`);return e.style.whiteSpace=`pre-wrap`,e.style.background=`var(--weiv-color-surface)`,e.style.border=`1px solid var(--weiv-color-border)`,e.style.borderRadius=`var(--weiv-radius-md)`,e.style.padding=`16px`,e.style.font=`13px/1.45 var(--weiv-font-mono)`,e.textContent=D,e},k.parameters={docs:{source:{code:D,language:`html`}}},O.parameters={...O.parameters,docs:{...O.parameters?.docs,source:{originalSource:`() => {
  const root = document.createElement("div");
  DialogBasic.mount(root);
  return root;
}`,...O.parameters?.docs?.source}}},k.parameters={...k.parameters,docs:{...k.parameters?.docs,source:{originalSource:`() => {
  const pre = document.createElement("pre");
  pre.style.whiteSpace = "pre-wrap";
  pre.style.background = "var(--weiv-color-surface)";
  pre.style.border = "1px solid var(--weiv-color-border)";
  pre.style.borderRadius = "var(--weiv-radius-md)";
  pre.style.padding = "16px";
  pre.style.font = "13px/1.45 var(--weiv-font-mono)";
  pre.textContent = usageCode;
  return pre;
}`,...k.parameters?.docs?.source}}},A=[`BasicOpenClose`,`UsageCode`]}))();export{O as BasicOpenClose,k as UsageCode,A as __namedExportsOrder,E as default};