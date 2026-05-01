import * as Root from "./App.mjs";
import * as Component_0 from "./TodoFooter.mjs";
import * as Component_1 from "./TodoHeader.mjs";
import * as Component_2 from "./TodoItem.mjs";
import * as Component_3 from "./TodoList.mjs";
import * as Component_4 from "./TodoTextInput.mjs";

export const components = {
  "TodoFooter": Component_0,
  "TodoHeader": Component_1,
  "TodoItem": Component_2,
  "TodoList": Component_3,
  "TodoTextInput": Component_4
};

export const root = Root;
export const cssPath = "./styles.css";

export function renderToString(props = {}) {
  return Root.renderToString(props, components);
}

export function mount(target, props = {}) {
  return Root.mount(target, props, components);
}
