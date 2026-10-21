type Listener = (paths: ReadonlySet<string> | null) => void;

const WEIV_OBSERVABLE = Symbol.for("weiv.observable");

type RootState = {
  pending: Map<NodeState, Set<string> | null>;
  scheduled: boolean;
};

type NodeState = {
  root: RootState;
  target: object;
  proxy: object;
  listeners: Set<Listener>;
  parents: Map<NodeState, Set<string>>;
};

const rawToNode = new WeakMap<object, NodeState>();
const proxyToNode = new WeakMap<object, NodeState>();

function isObject(value: unknown): value is object {
  return typeof value === "object" && value !== null;
}

function defineObservableBrand(target: object, node: NodeState) {
  Object.defineProperty(target, WEIV_OBSERVABLE, {
    value: node,
    enumerable: false,
    configurable: false,
    writable: false,
  });
}

function getObservableNode(value: unknown): NodeState | undefined {
  if (!isObject(value)) return undefined;
  const direct = proxyToNode.get(value);
  if (direct) return direct;
  return Reflect.get(value, WEIV_OBSERVABLE) as NodeState | undefined;
}

function unwrapValue<T>(value: T): T {
  if (!isObject(value)) return value;
  const node = getObservableNode(value);
  return (node?.target ?? value) as T;
}

function scheduleFlush(root: RootState) {
  if (root.scheduled) return;
  root.scheduled = true;
  queueMicrotask(() => {
    root.scheduled = false;
    if (root.pending.size === 0) return;

    const notifying = Array.from(root.pending);
    root.pending.clear();

    for (const [node, paths] of notifying) {
      for (const listener of node.listeners) {
        listener(paths);
      }
    }
  });
}

function linkParent(child: NodeState, parent: NodeState, key: PropertyKey) {
  if (typeof key === "symbol") return;
  let keys = child.parents.get(parent);
  if (!keys) child.parents.set(parent, (keys = new Set()));
  keys.add(String(key));
}

function unlinkParent(child: NodeState, parent: NodeState, key: PropertyKey) {
  const keys = child.parents.get(parent);
  keys?.delete(String(key));
  if (keys?.size === 0) child.parents.delete(parent);
}

function unlinkRemovedChildren(previous: unknown, next: unknown, parent: NodeState, key: PropertyKey) {
  if (!isObject(previous)) return;
  if (Object.is(previous, next)) return;

  const previousNode = rawToNode.get(previous);
  if (!previousNode) return;

  unlinkParent(previousNode, parent, key);
}

function markChanged(node: NodeState, key: PropertyKey) {
  const touchedRoots = new Set<RootState>();
  const queue: Array<{ node: NodeState; path: string | null; ancestors: Set<NodeState> }> = [
    { node, path: typeof key === "symbol" ? null : String(key), ancestors: new Set([node]) },
  ];
  while (queue.length > 0) {
    const current = queue.pop()!;
    const pending = current.node.root.pending;
    touchedRoots.add(current.node.root);
    const existing = pending.get(current.node);
    if (!pending.has(current.node)) {
      pending.set(current.node, current.path === null ? null : new Set([current.path]));
    } else if (current.path === null) {
      pending.set(current.node, null);
    } else {
      existing?.add(current.path);
    }
    for (const [parent, keys] of current.node.parents) {
      if (current.ancestors.has(parent)) {
        parent.root.pending.set(parent, null);
        touchedRoots.add(parent.root);
        continue;
      }
      for (const parentKey of keys) {
        queue.push({
          node: parent,
          path: current.path === null ? null : `${parentKey}.${current.path}`,
          ancestors: new Set([...current.ancestors, parent]),
        });
      }
    }
  }

  for (const root of touchedRoots) scheduleFlush(root);
}

function ensureObservableNode(target: object, root: RootState, parent: NodeState | null, key?: PropertyKey): NodeState {
  const existing = rawToNode.get(target);
  if (existing) {
    if (parent && key !== undefined) linkParent(existing, parent, key);
    return existing;
  }

  const node: NodeState = {
    root,
    target,
    proxy: undefined as unknown as object,
    listeners: new Set(),
    parents: new Map(),
  };
  if (parent && key !== undefined) linkParent(node, parent, key);

  const proxy = new Proxy(target, {
    get(currentTarget, prop, receiver) {
      const value = Reflect.get(currentTarget, prop, receiver);
      if (prop === WEIV_OBSERVABLE) return value;
      if (!isObject(value)) return value;
      return ensureObservableNode(value, root, node, prop).proxy;
    },

    set(currentTarget, prop, value, receiver) {
      const previous = Reflect.get(currentTarget, prop, receiver);
      const next = unwrapValue(value);
      unlinkRemovedChildren(previous, next, node, prop);

      const updated = Reflect.set(currentTarget, prop, next, receiver);
      if (!updated) return false;

      if (isObject(next)) {
        ensureObservableNode(next, root, node, prop);
      }

      if (!Object.is(previous, next)) {
        markChanged(node, prop);
        if (Array.isArray(currentTarget) && prop !== "length") markChanged(node, "length");
      }
      return true;
    },

    deleteProperty(currentTarget, prop) {
      const previous = Reflect.get(currentTarget, prop);
      const hadKey = Reflect.has(currentTarget, prop);
      const updated = Reflect.deleteProperty(currentTarget, prop);
      if (updated && hadKey) {
        unlinkRemovedChildren(previous, undefined, node, prop);
        markChanged(node, prop);
        if (Array.isArray(currentTarget) && prop !== "length") markChanged(node, "length");
      }
      return updated;
    },
  });

  node.proxy = proxy;
  defineObservableBrand(target, node);
  rawToNode.set(target, node);
  proxyToNode.set(proxy, node);
  return node;
}

export function observable<T extends object>(value: T): T {
  const existing = getObservableNode(value);
  if (existing) {
    return existing.proxy as T;
  }

  const root: RootState = {
    pending: new Map(),
    scheduled: false,
  };

  return ensureObservableNode(value, root, null).proxy as T;
}

export function subscribe<T extends object>(value: T, listener: Listener): () => void {
  const node = getObservableNode(value);
  if (!node) {
    throw new Error("subscribe() expects a value created by observable()");
  }
  node.listeners.add(listener);
  return () => {
    node.listeners.delete(listener);
  };
}

export function snapshot<T>(value: T): T {
  const seen = new WeakMap<object, object>();

  function clone(current: unknown): unknown {
    if (!isObject(current)) return current;

      const node = getObservableNode(current);
    const source = node?.target ?? current;

    const existing = seen.get(source);
    if (existing) return existing;

    const out: Record<string | symbol, unknown> | unknown[] = Array.isArray(source) ? [] : {};
    seen.set(source, out);

    for (const key of Reflect.ownKeys(source)) {
      const descriptor = Reflect.getOwnPropertyDescriptor(source, key);
      if (!descriptor || !descriptor.enumerable) continue;
      out[key as keyof typeof out] = clone(Reflect.get(source, key));
    }

    return Object.freeze(out);
  }

  return clone(value) as T;
}

export function isObservable(value: unknown): boolean {
  return getObservableNode(value) != null;
}

export function observableBrandSymbol(): symbol {
  return WEIV_OBSERVABLE;
}
