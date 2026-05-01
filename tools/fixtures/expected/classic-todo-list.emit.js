export const template = [
  { kind: "element", tag: "section", attributes: [{ name: "class", value: "todo-list" }], effects: [], children: [
    { kind: "conditional", condition: "props.items.length === 0", consequent: [
      { kind: "element", tag: "div", attributes: [{ name: "class", value: "todo-list__empty" }], effects: [], children: [
        { kind: "element", tag: "p", attributes: [{ name: "class", value: "todo-list__empty-title" }], effects: [], children: [
          { kind: "text", content: "Nothing in this lane yet" }
        ] },
        { kind: "element", tag: "span", attributes: [{ name: "class", value: "todo-list__empty-copy" }], effects: [], children: [
          { kind: "interpolation", expression: "props.showCompleted ? \"Completed work will land here.\" : \"Active work will land here.\"" }
        ] }
      ] }
    ], alternate: [
      { kind: "element", tag: "ul", attributes: [{ name: "class", value: "todo-list__items" }], effects: [], children: [
        { kind: "for", item: "item", iterable: "props.items", body: [
          { kind: "element", tag: "li", attributes: [], effects: [], children: [
            { kind: "component", tag: "TodoItem", effects: [{ kind: "bind", target: "item", expression: "item" }, { kind: "event", event: "toggle", expression: "emitToggle" }] }
          ] }
        ] }
      ] }
    ] }
  ] }
];
