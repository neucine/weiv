import * as AppBundle from "./bundle.mjs";
import { props as previewProps } from "./props.mjs";

const target = document.getElementById("app");
const props = globalThis.__WEIV_PROPS__ ?? previewProps;

if (target) {
  AppBundle.mount(target, props);
}

globalThis.__WEIV_BUNDLE__ = AppBundle;

export * from "./bundle.mjs";
export default AppBundle;
