import { readFile } from "node:fs/promises"

export function readSiblingPageSource(importMetaUrl: string) {
  return readFile(new URL("./page.tsx", importMetaUrl), "utf8")
}
