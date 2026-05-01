export const template = [
  { kind: "element", tag: "main", attributes: [{ name: "class", value: "todo-app" }], effects: [], children: [
    { kind: "element", tag: "div", attributes: [{ name: "class", value: "todo-app__shell" }], effects: [], children: [
      { kind: "element", tag: "header", attributes: [{ name: "class", value: "todo-app__hero" }], effects: [], children: [
        { kind: "element", tag: "p", attributes: [{ name: "class", value: "todo-app__eyebrow" }], effects: [], children: [
          { kind: "text", content: "Verification Example" }
        ] },
        { kind: "element", tag: "div", attributes: [{ name: "class", value: "todo-app__headline" }], effects: [], children: [
          { kind: "element", tag: "h1", attributes: [], effects: [], children: [
            { kind: "interpolation", expression: "props.title" }
          ] },
          { kind: "element", tag: "p", attributes: [{ name: "class", value: "todo-app__lede" }], effects: [], children: [
            { kind: "text", content: "Client runtime, nested components, scoped styles, and TS-backed helpers in one polished example." }
          ] }
        ] },
        { kind: "element", tag: "div", attributes: [{ name: "class", value: "todo-app__summary" }], effects: [], children: [
          { kind: "element", tag: "strong", attributes: [], effects: [], children: [
            { kind: "interpolation", expression: "summary()" }
          ] },
          { kind: "element", tag: "span", attributes: [], effects: [], children: [
            { kind: "interpolation", expression: "showCompleted ? \"Viewing completed tasks\" : \"Viewing active tasks\"" }
          ] }
        ] }
      ] },
      { kind: "element", tag: "section", attributes: [{ name: "class", value: "todo-app__panel" }], effects: [], children: [
        { kind: "element", tag: "div", attributes: [{ name: "class", value: "todo-app__panel-header" }], effects: [], children: [
          { kind: "element", tag: "div", attributes: [], effects: [], children: [
            { kind: "element", tag: "p", attributes: [{ name: "class", value: "todo-app__panel-label" }], effects: [], children: [
              { kind: "text", content: "Inbox" }
            ] },
            { kind: "element", tag: "h2", attributes: [], effects: [], children: [
              { kind: "text", content: "Product Todo Board" }
            ] }
          ] },
          { kind: "element", tag: "button", attributes: [{ name: "class", value: "todo-app__filter" }], effects: [{ kind: "event", event: "click", expression: "toggleCompletedFilter" }], children: [
            { kind: "interpolation", expression: "showCompleted ? \"Show active\" : \"Show completed\"" }
          ] }
        ] },
        { kind: "component", tag: "TodoList", effects: [{ kind: "bind", target: "items", expression: "visibleItems()" }, { kind: "bind", target: "showCompleted", expression: "showCompleted" }, { kind: "event", event: "toggle", expression: "toggleItem" }] }
      ] }
    ] }
  ] }
];
