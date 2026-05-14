export const themeName = "default";

export function applyThemeAttributes(element) {
  if (!element) return;
  element.setAttribute("data-theme", themeName);
}
