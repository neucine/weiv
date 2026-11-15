# Weiv

[English](README.md)

Weiv 是一个通过编译器构建页面的前端框架。模板、脚本和样式可以写在同一个 `.weiv` 文件里，不需要 JSX。状态变化时，它会直接更新相关的 DOM 节点。当前版本还支持组件插槽、项目内共享状态和路由。

Weiv 已经可以用于试做项目，但还没到 v1。依赖分析、大型应用验证、报错信息和编辑器体验仍在完善。进展见[项目状态](https://weiv.dev/status)。

## 快速开始

目前发布的编译器二进制文件支持 Apple Silicon Mac。其他平台需要自行准备兼容的二进制文件，并通过 `WEIV_BINARY_PATH` 指定路径。

```bash
npm i -D weivjs
npx weiv --help
npx weiv dev path/to/App.weiv
```

把 `path/to/App.weiv` 换成你的组件路径。需要打包部署时，可以运行：

```bash
npx weiv compile path/to/App.weiv
cd ./dist
bun server.ts
```

编译结果默认放在 `dist`。要换目录，可运行 `npx weiv compile path/to/App.weiv ./public`。

## 工作方式

编译器会分析组件中的模板和脚本，找出状态与页面之间的关系，再生成浏览器代码和样式。在支持的场景下，修改本地状态就会自动更新页面：状态立即变化，DOM 更新则合并到下一个微任务执行。项目内共享状态和外部可变数据的接入方式见[状态管理说明](packages/weiv/README.md#state-contract-managed-reactivity-by-default)。

使用发布版时，编译器和运行时版本需要匹配。CLI、构建工具集成和当前限制详见[英文 README](README.md)。有问题或建议，欢迎到 [GitHub Issues](https://github.com/neucine/weiv/issues) 交流。
