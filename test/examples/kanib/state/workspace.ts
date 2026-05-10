import { observable } from "@weiv/runtime";

export type WorkspaceSummary = {
  id: string;
  name: string;
  key: string;
  issueCount: number;
  openCount: number;
};

export type WorkspaceMetric = {
  id: string;
  label: string;
  value: string;
  change: number;
};

export type WorkspaceIssue = {
  id: string;
  workspaceId: string;
  title: string;
  summary: string;
  detail: string;
  owner: string;
  status: "backlog" | "in-progress" | "review" | "done";
  priority: "low" | "medium" | "high";
  updatedMinutesAgo: number;
  watchers: number;
};

export type WorkspaceMember = {
  id: string;
  workspaceId: string;
  name: string;
  role: string;
  focus: string;
};

export interface WorkspaceSharedState {
  currentWorkspaceId: string;
  selectedIssueId: string;
  notifications: number;
  saveTick: number;
  currentPath: string;
  externalSaveTick: number;
}

export const workspaceShared: WorkspaceSharedState = observable({
  currentWorkspaceId: "compiler-lab",
  selectedIssueId: "iss-102",
  notifications: 4,
  saveTick: 0,
  currentPath: "/workspaces/compiler-lab",
  externalSaveTick: 0,
});

type RouterLike = {
  push(path: string): void | Promise<void>;
  replace(path: string): void | Promise<void>;
};

const workspaceCatalog: WorkspaceSummary[] = [
  { id: "compiler-lab", name: "Compiler Lab", key: "CL", issueCount: 6, openCount: 4 },
  { id: "design-systems", name: "Design Systems", key: "DS", issueCount: 4, openCount: 3 },
];

const workspaceMetrics: Record<string, WorkspaceMetric[]> = {
  "compiler-lab": [
    { id: "m-1", label: "Open issues", value: "4", change: -1 },
    { id: "m-2", label: "Review queue", value: "2", change: 1 },
    { id: "m-3", label: "Cycle time", value: "2.6d", change: -8 },
  ],
  "design-systems": [
    { id: "m-4", label: "Open issues", value: "3", change: 0 },
    { id: "m-5", label: "Review queue", value: "1", change: -1 },
    { id: "m-6", label: "Cycle time", value: "3.1d", change: 4 },
  ],
};

export const issues: WorkspaceIssue[] = observable([
  {
    id: "iss-101",
    workspaceId: "compiler-lab",
    title: "Stabilize router + app bundle hydration",
    summary: "The routed Kanib app should mount cleanly through the bundle path.",
    detail: "Make the shell stable, preserve nested routes, and avoid duplicate bootstrap behavior between preview and emitted bundle.",
    owner: "Avery",
    status: "in-progress",
    priority: "high",
    updatedMinutesAgo: 18,
    watchers: 3,
  },
  {
    id: "iss-102",
    workspaceId: "compiler-lab",
    title: "Replace the old demo with a product-grade test base",
    summary: "Translate a Kaneo-like issue workflow into a compact Weiv example.",
    detail: "Keep the app understandable to humans while still pressuring router, slots, shared state, and selective updates.",
    owner: "Mika",
    status: "review",
    priority: "high",
    updatedMinutesAgo: 44,
    watchers: 5,
  },
  {
    id: "iss-103",
    workspaceId: "compiler-lab",
    title: "Tighten diagnostics JSON contract",
    summary: "Make the compiler diagnostics surface stable enough for editor tooling.",
    detail: "Keep the JSON shape documented, add formatter coverage, and stop letting CLI formatting become the source of truth.",
    owner: "Noa",
    status: "backlog",
    priority: "medium",
    updatedMinutesAgo: 91,
    watchers: 2,
  },
  {
    id: "iss-104",
    workspaceId: "compiler-lab",
    title: "Audit slot usage in the flagship app",
    summary: "Make sure shell, panel, and empty-state slots feel product-native.",
    detail: "Keep dedicated slot fixtures for edge cases, but make the flagship app use named and fallback slots in a believable way.",
    owner: "Lina",
    status: "done",
    priority: "low",
    updatedMinutesAgo: 160,
    watchers: 1,
  },
  {
    id: "iss-201",
    workspaceId: "design-systems",
    title: "Document workspace shell patterns",
    summary: "Turn shell composition into a reusable reference for later apps.",
    detail: "Capture sidebar, toolbar, and secondary-aside layout guidance so new example apps can inherit the same pattern.",
    owner: "Sana",
    status: "review",
    priority: "medium",
    updatedMinutesAgo: 36,
    watchers: 4,
  },
  {
    id: "iss-202",
    workspaceId: "design-systems",
    title: "Theme the empty states",
    summary: "Improve empty state density and fallback slot presentation.",
    detail: "Use clearer copy, cleaner spacing, and action slots that still read well in narrow layouts.",
    owner: "Theo",
    status: "in-progress",
    priority: "low",
    updatedMinutesAgo: 72,
    watchers: 2,
  },
]);

const members: WorkspaceMember[] = [
  { id: "mem-1", workspaceId: "compiler-lab", name: "Avery", role: "Staff Engineer", focus: "Runtime" },
  { id: "mem-2", workspaceId: "compiler-lab", name: "Mika", role: "Product Engineer", focus: "App examples" },
  { id: "mem-3", workspaceId: "compiler-lab", name: "Noa", role: "DX Engineer", focus: "Diagnostics" },
  { id: "mem-4", workspaceId: "design-systems", name: "Sana", role: "Design Engineer", focus: "Shell patterns" },
  { id: "mem-5", workspaceId: "design-systems", name: "Theo", role: "Frontend Engineer", focus: "States" },
];

const externalSaveListeners: Array<() => void> = [];
let activeRouter: RouterLike | null = null;

export function listWorkspaces() {
  return workspaceCatalog;
}

export function listMetrics(workspaceId: string) {
  return workspaceMetrics[workspaceId] || [];
}

export function listIssues(workspaceId: string) {
  return issues.filter((issue) => issue.workspaceId === workspaceId);
}

export function listMembers(workspaceId: string) {
  return members.filter((member) => member.workspaceId === workspaceId);
}

export function findWorkspace(workspaceId: string) {
  return workspaceCatalog.find((workspace) => workspace.id === workspaceId) || workspaceCatalog[0];
}

export function findIssue(issueId: string) {
  return issues.find((issue) => issue.id === issueId) || null;
}

export function setCurrentWorkspaceId(workspaceId: string) {
  workspaceShared.currentWorkspaceId = workspaceId;
}

export function setSelectedIssueId(issueId: string) {
  workspaceShared.selectedIssueId = issueId;
}

export function clearNotifications() {
  workspaceShared.notifications = 0;
}

export function bumpNotifications() {
  workspaceShared.notifications += 1;
}

export function registerExternalSaveListener(listener: () => void) {
  externalSaveListeners.push(listener);
}

export function emitExternalSavePulse() {
  workspaceShared.externalSaveTick += 1;
  for (const listener of externalSaveListeners) {
    listener();
  }
}

export function cycleIssueStatus(issueId: string) {
  const issue = findIssue(issueId);
  if (!issue) return;

  const nextStatus = issue.status === "backlog"
    ? "in-progress"
    : issue.status === "in-progress"
      ? "review"
      : issue.status === "review"
        ? "done"
        : "backlog";

  issue.status = nextStatus;
  issue.updatedMinutesAgo = 0;
  issue.watchers += 1;
  workspaceShared.saveTick += 1;
}

export function setWorkspaceRouter(router: RouterLike) {
  activeRouter = router;
}

export function syncRouteState(path: string, workspaceId?: string, issueId?: string) {
  workspaceShared.currentPath = path;
  if (workspaceId) {
    workspaceShared.currentWorkspaceId = workspaceId;
  }
  if (issueId) {
    workspaceShared.selectedIssueId = issueId;
    return;
  }

  const workspaceIssues = listIssues(workspaceShared.currentWorkspaceId);
  if (workspaceIssues.length > 0) {
    workspaceShared.selectedIssueId = workspaceIssues[0].id;
  }
}

export function navigateTo(path: string) {
  activeRouter?.push(path);
}

export function replaceWith(path: string) {
  activeRouter?.replace(path);
}

export function workspaceRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}`;
}

export function issuesRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/issues`;
}

export function boardRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/board`;
}

export function issueRoute(workspaceId: string, issueId: string) {
  return `/workspaces/${workspaceId}/issues/${issueId}`;
}

export function membersRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/members`;
}

export function settingsRoute(workspaceId: string) {
  return `/workspaces/${workspaceId}/settings`;
}
