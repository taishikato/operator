import assert from "node:assert/strict"
import { test } from "node:test"

import { readSiblingPageSource } from "../../page-source-test-helper.ts"

test("Add Project route renders the existing Add Project form", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.match(source, /import\s+\{\s*AddProjectForm\s+\}/)
  assert.match(source, /<AddProjectForm\s*\/>/)
})

test("Add Project route handles explicit database apply state", async () => {
  const source = await readSiblingPageSource(import.meta.url)

  assert.match(source, /databaseStatus\s*===\s*"requires_explicit_apply"/)
  assert.match(source, /Operator database schema is out of date/)
})
