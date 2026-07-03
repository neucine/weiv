export default {
  title: "Theme Default/Foundations",
};

export const ButtonsAndFields = () => {
  const root = document.createElement("div");
  root.style.display = "grid";
  root.style.gap = "16px";
  root.style.maxWidth = "420px";

  const buttonRow = document.createElement("div");
  buttonRow.style.display = "flex";
  buttonRow.style.gap = "12px";

  const primary = document.createElement("button");
  primary.className = "wv-button";
  primary.textContent = "Primary Action";

  const secondary = document.createElement("button");
  secondary.className = "wv-button";
  secondary.style.background = "var(--weiv-color-surface)";
  secondary.style.color = "var(--weiv-color-text)";
  secondary.style.borderColor = "var(--weiv-color-border)";
  secondary.textContent = "Secondary";

  buttonRow.append(primary, secondary);

  const field = document.createElement("div");
  field.className = "wv-field";

  const label = document.createElement("label");
  label.className = "wv-label";
  label.textContent = "Project name";
  label.htmlFor = "project-name";

  const input = document.createElement("input");
  input.className = "wv-input";
  input.id = "project-name";
  input.placeholder = "Kanib Redesign";

  const help = document.createElement("p");
  help.className = "wv-help";
  help.textContent = "Used in roadmap and release notes.";

  field.append(label, input, help);
  root.append(buttonRow, field);
  return root;
};

ButtonsAndFields.parameters = {
  docs: {
    source: {
      code: `import "@weivjs/ui-theme-default/tokens.css";
import "@weivjs/ui-theme-default/components.css";

const button = document.createElement("button");
button.className = "wv-button";

const input = document.createElement("input");
input.className = "wv-input";`,
    },
  },
};
