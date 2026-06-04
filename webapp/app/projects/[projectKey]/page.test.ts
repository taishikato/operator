import assert from "node:assert/strict"
import { test } from "node:test"

import { readSiblingPageSource } from "../../page-source-test-helper.ts"

test("Project page links to Project settings", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.match(source, /\/projects\/\$\{encodeURIComponent\(project\.key\)\}\/settings/)
  assert.match(source, />\s*Settings\s*</)
})

test("Project page links back to Projects and Add Project", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.match(source, /href="\/"/)
  assert.match(source, />\s*Projects\s*</)
  assert.match(source, /href="\/projects\/new"/)
  assert.match(source, />\s*Add Project\s*</)
})
