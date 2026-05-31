import assert from "node:assert/strict"
import { test } from "node:test"

import { applyOperatorSchemaWithAtlas } from "./schema-apply.ts"

test("applyOperatorSchemaWithAtlas reports spawn failures without masking them", async () => {
  await withEmptyPath(async () => {
    await assert.rejects(
      () =>
        applyOperatorSchemaWithAtlas({
          databasePath: "/tmp/operator.db",
          schemaSql: "CREATE TABLE operator_metadata (key text PRIMARY KEY);",
        }),
      /atlas schema apply failed: .*ENOENT/
    )
  })
})

async function withEmptyPath(callback: () => Promise<void>) {
  const originalPath = process.env.PATH
  process.env.PATH = ""

  try {
    await callback()
  } finally {
    if (originalPath === undefined) {
      delete process.env.PATH
    } else {
      process.env.PATH = originalPath
    }
  }
}
