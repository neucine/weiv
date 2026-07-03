import type { StorybookConfig } from "@storybook/html-vite";
import { weiv } from "../../../packages/weiv/dist/vite.mjs";

const config: StorybookConfig = {
  framework: "@storybook/html-vite",
  stories: ["../stories/**/*.stories.@(js|ts)"],
  addons: ["@storybook/addon-docs"],
  async viteFinal(config) {
    config.plugins = config.plugins ?? [];
    config.plugins.push(weiv());
    return config;
  },
};

export default config;
