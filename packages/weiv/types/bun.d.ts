export type BunPluginBuild = {
  onResolve(args: { filter: RegExp }, callback: (args: { path: string }) => { path: string; namespace?: string } | Promise<{ path: string; namespace?: string }>): void;
  onLoad(args: { filter: RegExp; namespace?: string }, callback: (args: { path: string }) => { contents: string; loader: "js" } | Promise<{ contents: string; loader: "js" }>): void;
};

export type WeivBunPlugin = {
  name: string;
  setup(build: BunPluginBuild): void;
};

export type WeivBunPluginOptions = Record<string, never>;

export function weiv(options?: WeivBunPluginOptions): WeivBunPlugin;
