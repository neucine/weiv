import { suffix } from "./punctuation.js";

export function formatTitle(value) {
  return `Hello, ${value}${suffix}`;
}
