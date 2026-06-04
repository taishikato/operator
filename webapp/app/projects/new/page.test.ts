import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

test("Add Project route renders the existing Add Project form", async () => {
  const source = await readFile(new URL("./page.tsx", import.meta.url), "utf8")

  assert.match(source, /import\s+\{\s*AddProjectForm\s+\}/)
  assert.match(source, /<AddProjectForm\s*\/>/)
})

test("Add Project route handles explicit database apply state", async () => {
  const source = await readFile(new URL("./page.tsx", import.meta.url), "utf8")

  assert.match(source, /databaseStatus\s*===\s*"requires_explicit_apply"/)
  assert.match(source, /Operator database schema is out of date/)
})
