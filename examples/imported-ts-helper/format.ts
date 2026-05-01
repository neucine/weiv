import { suffix } from "./punctuation.ts";

export function formatTitle(value: string) {
  return `TS hello, ${value}${suffix}`;
}
