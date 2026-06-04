import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

test("Project page links to Project settings", async () => {
  const source = await readFile(new URL("./page.tsx", import.meta.url), "utf8")

  assert.match(source, /\/projects\/\$\{encodeURIComponent\(project\.key\)\}\/settings/)
  assert.match(source, />\s*Settings\s*</)
})

test("Project page links back to Projects and Add Project", async () => {
  const source = await readFile(new URL("./page.tsx", import.meta.url), "utf8")

  assert.match(source, /href="\/"/)
  assert.match(source, />\s*Projects\s*</)
  assert.match(source, /href="\/projects\/new"/)
  assert.match(source, />\s*Add Project\s*</)
})
