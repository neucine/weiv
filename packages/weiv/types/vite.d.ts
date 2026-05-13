export type WeivVitePlugin = {
  name: string;
  enforce?: "pre" | "post";
  resolveId?: (id: string) => string | null | undefined;
  load?: (id: string) => string | null | undefined;
  transform?: (code: string, id: string) => { code: string; map: null } | null | undefined;
};

export type WeivVitePluginOptions = Record<string, never>;

export function weiv(options?: WeivVitePluginOptions): WeivVitePlugin;
