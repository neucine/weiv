const std = @import("std");

const runtime_source =
    \\export function escapeHtml(value) {
    \\  return String(value)
    \\    .replaceAll("&", "&amp;")
    \\    .replaceAll("<", "&lt;")
    \\    .replaceAll(">", "&gt;")
    \\    .replaceAll("\"", "&quot;")
    \\    .replaceAll("'", "&#39;");
    \\}
    \\
    \\export function evaluate(expression, scope) {
    \\  const entries = Object.entries(scope);
    \\  const names = entries.map(([name]) => name);
    \\  const values = entries.map(([, value]) => value);
    \\  return Function(...names, `return (${expression});`)(...values);
    \\}
    \\
    \\export function renderNodes(nodes, scope, components, scopeId = null, slots = {}) {
    \\  let out = "";
    \\  for (const node of nodes) {
    \\    out += renderNode(node, scope, components, scopeId, slots);
    \\  }
    \\  return out;
    \\}
    \\
    \\export function renderAttributes(attributes, effects, scope, scopeId) {
    \\  const rendered = new Map();
    \\  if (scopeId) {
    \\    rendered.set("data-weiv-scope", scopeId);
    \\  }
    \\  for (const attribute of attributes) {
    \\    rendered.set(attribute.name, attribute.value === null ? true : attribute.value);
    \\  }
    \\  for (const effect of effects) {
    \\    if (effect.kind !== "bind") continue;
    \\    rendered.set(effect.target, evaluate(effect.expression, scope));
    \\  }
    \\  let out = "";
    \\  for (const [name, value] of rendered.entries()) {
    \\    if (value === false || value === null || value === undefined) continue;
    \\    if (value === true) {
    \\      out += ` ${name}`;
    \\      continue;
    \\    }
    \\    out += ` ${name}="${escapeHtml(value)}"`;
    \\  }
    \\  return out;
    \\}
    \\
    \\export function renderNode(node, scope, components, scopeId = null, slots = {}) {
    \\  switch (node.kind) {
    \\    case "text":
    \\      return escapeHtml(node.content);
    \\    case "interpolation":
    \\      return escapeHtml(evaluate(node.expression, scope));
    \\    case "element": {
    \\      const attrs = renderAttributes(node.attributes, node.effects, scope, scopeId);
    \\      const inner = renderNodes(node.children, scope, components, scopeId, slots);
    \\      return `<${node.tag}${attrs}>${inner}</${node.tag}>`;
    \\    }
    \\    case "conditional":
    \\      return evaluate(node.condition, scope)
    \\        ? renderNodes(node.consequent, scope, components, scopeId, slots)
    \\        : renderNodes(node.alternate, scope, components, scopeId, slots);
    \\    case "for": {
    \\      const iterable = evaluate(node.iterable, scope) ?? [];
    \\      let out = "";
    \\      for (const item of iterable) {
    \\        out += renderNodes(node.body, { ...scope, [node.item]: item }, components, scopeId, slots);
    \\      }
    \\      return out;
    \\    }
    \\    case "component": {
    \\      const component = components[node.tag];
    \\      if (!component || typeof component.renderToString !== "function") {
    \\        throw new Error(`Missing component renderer for ${node.tag}`);
    \\      }
    \\      const props = {};
    \\      for (const effect of node.effects) {
    \\        if (effect.kind === "bind") {
    \\          props[effect.target] = evaluate(effect.expression, scope);
    \\        }
    \\      }
    \\      const childSlots = {};
    \\      for (const [slotName, provision] of Object.entries(node.slots ?? {})) {
    \\        childSlots[slotName] = { nodes: provision.nodes, scope };
    \\      }
    \\      return component.renderToString(props, components, childSlots);
    \\    }
    \\    case "slot": {
    \\      const slotName = node.name ?? "default";
    \\      const provided = slots[slotName];
    \\      if (provided) {
    \\        return renderNodes(provided.nodes, provided.scope, components, scopeId, {});
    \\      }
    \\      return renderNodes(node.fallback, scope, components, scopeId, {});
    \\    }
    \\    default:
    \\      throw new Error(`Unsupported node kind: ${node.kind}`);
    \\  }
    \\}
    \\
    \\export function mountNodes(nodes, scope, components, scopeId = null, rerenderRoot = () => {}, eventHandlers = {}, instance = null, slots = {}) {
    \\  const fragment = document.createDocumentFragment();
    \\  for (const node of nodes) {
    \\    fragment.append(mountNode(node, scope, components, scopeId, rerenderRoot, eventHandlers, instance, slots));
    \\  }
    \\  return fragment;
    \\}
    \\
    \\export function mountNode(node, scope, components, scopeId = null, rerenderRoot = () => {}, eventHandlers = {}, instance = null, slots = {}) {
    \\  switch (node.kind) {
    \\    case "text":
    \\      return document.createTextNode(String(node.content));
    \\    case "interpolation":
    \\      return document.createTextNode(String(evaluate(node.expression, scope)));
    \\    case "element": {
    \\      const element = document.createElement(node.tag);
    \\      applyDomAttributes(element, node.attributes, node.effects, scope, scopeId);
    \\      attachDomEvents(element, node.effects, scope, rerenderRoot, eventHandlers, instance);
    \\      element.append(mountNodes(node.children, scope, components, scopeId, rerenderRoot, eventHandlers, instance, slots));
    \\      applyAutofocus(element);
    \\      return element;
    \\    }
    \\    case "conditional":
    \\      return evaluate(node.condition, scope)
    \\        ? mountNodes(node.consequent, scope, components, scopeId, rerenderRoot, eventHandlers, instance, slots)
    \\        : mountNodes(node.alternate, scope, components, scopeId, rerenderRoot, eventHandlers, instance, slots);
    \\    case "for": {
    \\      const fragment = document.createDocumentFragment();
    \\      const iterable = evaluate(node.iterable, scope) ?? [];
    \\      for (const item of iterable) {
    \\        const childScope = { ...scope, [node.item]: item };
    \\        fragment.append(mountNodes(node.body, childScope, components, scopeId, rerenderRoot, eventHandlers, instance, slots));
    \\      }
    \\      return fragment;
    \\    }
    \\    case "component": {
    \\      const component = components[node.tag];
    \\      if (!component || typeof component.mountIntoBoundary !== "function") {
    \\        throw new Error(`Missing component DOM renderer for ${node.tag}`);
    \\      }
    \\      const props = {};
    \\      const childEventHandlers = {};
    \\      for (const effect of node.effects) {
    \\        if (effect.kind === "bind") {
    \\          props[effect.target] = evaluate(effect.expression, scope);
    \\        } else if (effect.kind === "event") {
    \\          childEventHandlers[effect.event] = (payload) => {
    \\            const beforeScope = snapshotScopeForRerender(scope, instance);
    \\            const currentScope = currentScopeForEvents(scope, instance);
    \\            const resolved = evaluate(effect.expression, currentScope);
    \\            let result = resolved;
    \\            if (typeof resolved === "function") {
    \\              result = resolved(payload);
    \\            }
    \\            if (shouldRerender(beforeScope, scope, instance)) {
    \\              rerenderRoot();
    \\            }
    \\            return result;
    \\          };
    \\        }
    \\      }
    \\      const childSlots = {};
    \\      for (const [slotName, provision] of Object.entries(node.slots ?? {})) {
    \\        childSlots[slotName] = { nodes: provision.nodes, scope };
    \\      }
    \\      const boundary = createBoundary(`component:${node.tag}`);
    \\      component.mountIntoBoundary(boundary.start, boundary.end, props, components, childEventHandlers, childSlots);
    \\      return boundary.fragment;
    \\    }
    \\    case "slot": {
    \\      const slotName = node.name ?? "default";
    \\      const provided = slots[slotName];
    \\      if (provided) {
    \\        return mountNodes(provided.nodes, provided.scope, components, scopeId, rerenderRoot, eventHandlers, instance, {});
    \\      }
    \\      return mountNodes(node.fallback, scope, components, scopeId, rerenderRoot, eventHandlers, instance, {});
    \\    }
    \\    default:
    \\      throw new Error(`Unsupported node kind: ${node.kind}`);
    \\  }
    \\}
    \\
    \\export function createBoundary(label = "weiv") {
    \\  const fragment = document.createDocumentFragment();
    \\  const start = document.createComment(`${label}:start`);
    \\  const end = document.createComment(`${label}:end`);
    \\  fragment.append(start);
    \\  fragment.append(end);
    \\  return { fragment, start, end };
    \\}
    \\
    \\export function replaceBoundary(start, end, content) {
    \\  const parent = start.parentNode;
    \\  if (!parent || parent !== end.parentNode) {
    \\    throw new Error("Component boundary is detached");
    \\  }
    \\  let current = start.nextSibling;
    \\  while (current && current !== end) {
    \\    const next = current.nextSibling;
    \\    parent.removeChild(current);
    \\    current = next;
    \\  }
    \\  parent.insertBefore(content, end);
    \\}
    \\
    \\function applyDomAttributes(element, attributes, effects, scope, scopeId) {
    \\  if (scopeId) {
    \\    element.setAttribute("data-weiv-scope", scopeId);
    \\  }
    \\  for (const attribute of attributes) {
    \\    if (attribute.value === null) {
    \\      element.setAttribute(attribute.name, "");
    \\    } else {
    \\      element.setAttribute(attribute.name, String(attribute.value));
    \\    }
    \\  }
    \\  for (const effect of effects) {
    \\    if (effect.kind !== "bind") continue;
    \\    const value = evaluate(effect.expression, scope);
    \\    if (effect.target === "checked" || effect.target === "disabled" || effect.target === "selected") {
    \\      element[effect.target] = Boolean(value);
    \\      if (value) {
    \\        element.setAttribute(effect.target, "");
    \\      } else {
    \\        element.removeAttribute(effect.target);
    \\      }
    \\      continue;
    \\    }
    \\    if (value === false || value === null || value === undefined) {
    \\      element.removeAttribute(effect.target);
    \\      continue;
    \\    }
    \\    if (value === true) {
    \\      element.setAttribute(effect.target, "");
    \\      continue;
    \\    }
    \\    element.setAttribute(effect.target, String(value));
    \\  }
    \\}
    \\
    \\function attachDomEvents(element, effects, scope, rerenderRoot, eventHandlers, instance) {
    \\  for (const effect of effects) {
    \\    if (effect.kind !== "event") continue;
    \\    element.addEventListener(effect.event, (domEvent) => {
    \\      const beforeScope = snapshotScopeForRerender(scope, instance);
    \\      const currentScope = currentScopeForEvents(scope, instance);
    \\      const resolved = evaluate(effect.expression, currentScope);
    \\      if (typeof resolved === "function") {
    \\        resolved(domEvent);
    \\      }
    \\      if (shouldRerender(beforeScope, scope, instance)) {
    \\        rerenderRoot();
    \\      }
    \\    });
    \\  }
    \\}
    \\
    \\function applyAutofocus(element) {
    \\  if (!element.hasAttribute || !element.hasAttribute("autofocus")) {
    \\    return;
    \\  }
    \\  queueMicrotask(() => {
    \\    if (!element.isConnected || typeof element.focus !== "function") {
    \\      return;
    \\    }
    \\    element.focus();
    \\    if (typeof element.select === "function") {
    \\      element.select();
    \\    }
    \\  });
    \\}
    \\
    \\function snapshotScopeForRerender(scope, instance) {
    \\  const current = currentScopeForEvents(scope, instance);
    \\  return cloneScope(current);
    \\}
    \\
    \\function shouldRerender(beforeScope, scope, instance) {
    \\  const afterScope = currentScopeForEvents(scope, instance);
    \\  return hasScopeChanged(beforeScope, afterScope);
    \\}
    \\
    \\function cloneScope(scope) {
    \\  const snapshot = {};
    \\  for (const key of Object.keys(scope)) {
    \\    snapshot[key] = scope[key];
    \\  }
    \\  return snapshot;
    \\}
    \\
    \\function hasScopeChanged(beforeScope, afterScope) {
    \\  const beforeKeys = Object.keys(beforeScope);
    \\  const afterKeys = Object.keys(afterScope);
    \\  if (beforeKeys.length !== afterKeys.length) {
    \\    return true;
    \\  }
    \\  for (const key of afterKeys) {
    \\    if (!Object.prototype.hasOwnProperty.call(beforeScope, key)) {
    \\      return true;
    \\    }
    \\    if (!Object.is(beforeScope[key], afterScope[key])) {
    \\      return true;
    \\    }
    \\  }
    \\  return false;
    \\}
    \\
    \\function currentScopeForEvents(scope, instance) {
    \\  if (!instance || typeof instance.refresh !== "function") {
    \\    return scope;
    \\  }
    \\  return { ...instance.refresh(), ...scope };
    \\}
    \\
;

pub fn emitSharedRuntime(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, runtime_source);
}
