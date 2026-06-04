import assert from "node:assert/strict"
import { test } from "node:test"

import { readSiblingPageSource } from "../../page-source-test-helper.ts"

test("Project page links to Project settings", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.match(source, /\/projects\/\$\{encodeURIComponent\(project\.key\)\}\/settings/)
  assert.match(source, />\s*Settings\s*</)
})

test("Project page omits shared navigation links from its local header", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.doesNotMatch(source, /FolderKanban/)
  assert.doesNotMatch(source, />\s*Projects\s*</)
  assert.doesNotMatch(source, /href="\/projects\/new"/)
  assert.doesNotMatch(source, />\s*Add Project\s*</)
  assert.doesNotMatch(source, /Project \{project\.key\}/)
})
