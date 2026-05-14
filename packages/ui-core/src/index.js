const idCounters = new Map();

export function createId(prefix = "weiv") {
  const current = idCounters.get(prefix) ?? 0;
  const next = current + 1;
  idCounters.set(prefix, next);
  return `${prefix}-${next}`;
}

export function createControllableState(initialValue) {
  let value = initialValue;
  const listeners = new Set();

  function notify() {
    for (const listener of listeners) listener(value);
  }

  return {
    get value() {
      return value;
    },
    set(nextValue) {
      if (Object.is(value, nextValue)) return;
      value = nextValue;
      notify();
    },
    subscribe(listener) {
      listeners.add(listener);
      listener(value);
      return () => listeners.delete(listener);
    }
  };
}

export function createDialogController({ initialOpen = false } = {}) {
  const state = createControllableState(Boolean(initialOpen));

  return {
    get open() {
      return state.value;
    },
    openDialog() {
      state.set(true);
    },
    closeDialog() {
      state.set(false);
    },
    toggleDialog() {
      state.set(!state.value);
    },
    subscribe(listener) {
      return state.subscribe(listener);
    }
  };
}

export function createDisclosureController({ initialExpanded = false } = {}) {
  const state = createControllableState(Boolean(initialExpanded));

  return {
    get expanded() {
      return state.value;
    },
    expand() {
      state.set(true);
    },
    collapse() {
      state.set(false);
    },
    toggle() {
      state.set(!state.value);
    },
    subscribe(listener) {
      return state.subscribe(listener);
    }
  };
}
