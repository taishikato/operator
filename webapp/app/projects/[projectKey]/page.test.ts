import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

test("Project page links to Project settings", async () => {
  const source = await readFile(new URL("./page.tsx", import.meta.url), "utf8")

  assert.match(source, /\/projects\/\$\{encodeURIComponent\(project\.key\)\}\/settings/)
  assert.match(source, />\s*Settings\s*</)
})
