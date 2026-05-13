type Listener = () => void;

const WEIV_OBSERVABLE = Symbol.for("weiv.observable");

type RootState = {
  pending: Set<NodeState>;
  scheduled: boolean;
};

type NodeState = {
  root: RootState;
  target: object;
  proxy: object;
  listeners: Set<Listener>;
  parents: Set<NodeState>;
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

    for (const node of notifying) {
      for (const listener of node.listeners) {
        listener();
      }
    }
  });
}

function linkParent(child: NodeState, parent: NodeState) {
  child.parents.add(parent);
}

function unlinkParent(child: NodeState, parent: NodeState) {
  child.parents.delete(parent);
}

function unlinkRemovedChildren(previous: unknown, next: unknown, parent: NodeState) {
  if (!isObject(previous)) return;
  if (Object.is(previous, next)) return;

  const previousNode = rawToNode.get(previous);
  if (!previousNode) return;

  unlinkParent(previousNode, parent);
}

function markChanged(node: NodeState) {
  const queue = [node];
  const seen = new Set<NodeState>();

  while (queue.length > 0) {
    const current = queue.pop()!;
    if (seen.has(current)) continue;
    seen.add(current);
    current.root.pending.add(current);
    for (const parent of current.parents) {
      queue.push(parent);
    }
  }

  scheduleFlush(node.root);
}

function ensureObservableNode(target: object, root: RootState, parent: NodeState | null): NodeState {
  const existing = rawToNode.get(target);
  if (existing) {
    if (parent) linkParent(existing, parent);
    return existing;
  }

  const node: NodeState = {
    root,
    target,
    proxy: undefined as unknown as object,
    listeners: new Set(),
    parents: new Set(),
  };
  if (parent) linkParent(node, parent);

  const proxy = new Proxy(target, {
    get(currentTarget, prop, receiver) {
      const value = Reflect.get(currentTarget, prop, receiver);
      if (prop === WEIV_OBSERVABLE) return value;
      if (!isObject(value)) return value;
      return ensureObservableNode(value, root, node).proxy;
    },

    set(currentTarget, prop, value, receiver) {
      const previous = Reflect.get(currentTarget, prop, receiver);
      const next = unwrapValue(value);
      unlinkRemovedChildren(previous, next, node);

      const updated = Reflect.set(currentTarget, prop, next, receiver);
      if (!updated) return false;

      if (isObject(next)) {
        ensureObservableNode(next, root, node);
      }

      if (!Object.is(previous, next)) {
        markChanged(node);
      }
      return true;
    },

    deleteProperty(currentTarget, prop) {
      const previous = Reflect.get(currentTarget, prop);
      const hadKey = Reflect.has(currentTarget, prop);
      const updated = Reflect.deleteProperty(currentTarget, prop);
      if (updated && hadKey) {
        unlinkRemovedChildren(previous, undefined, node);
        markChanged(node);
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
    pending: new Set(),
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
