export interface WorkspaceSharedState {
  selectedItemId: string;
  notifications: number;
  pulse: number;
}

export const workspaceShared: WorkspaceSharedState = {
  selectedItemId: "activity-2",
  notifications: 3,
  pulse: 0,
};

const externalPulseListeners: Array<() => void> = [];

export function setSelectedItemId(id: string) {
  workspaceShared.selectedItemId = id;
}

export function bumpNotifications() {
  workspaceShared.notifications += 1;
}

export function clearNotifications() {
  workspaceShared.notifications = 0;
}

export function bumpSharedPulse() {
  workspaceShared.pulse += 1;
}

export function registerExternalPulseListener(listener: () => void) {
  externalPulseListeners.push(listener);
}

export function emitExternalPulse() {
  for (const listener of externalPulseListeners) {
    listener();
  }
}
