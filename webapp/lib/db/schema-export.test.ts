import assert from "node:assert/strict"
import { test } from "node:test"

import { exportOperatorSchemaSql } from "./schema-export.ts"

test("exportOperatorSchemaSql exports the Operator bootstrap metadata table from Drizzle schema", () => {
  const sql = exportOperatorSchemaSql()

  assert.match(sql, /CREATE TABLE [`"]?operator_metadata[`"]?/i)
  assert.match(sql, /`key` text PRIMARY KEY/i)
  assert.match(sql, /`value` text NOT NULL/i)
  assert.match(sql, /`updated_at` text NOT NULL/i)
})

test("exportOperatorSchemaSql reports spawn failures without masking them", () => {
  withEmptyPath(() => {
    assert.throws(
      () => exportOperatorSchemaSql(),
      /drizzle-kit export failed: .*ENOENT/
    )
  })
})

function withEmptyPath(callback: () => void) {
  const originalPath = process.env.PATH
  process.env.PATH = ""

  try {
    callback()
  } finally {
    if (originalPath === undefined) {
      delete process.env.PATH
    } else {
      process.env.PATH = originalPath
    }
  }
}
