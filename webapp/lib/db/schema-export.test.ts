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

test("exportOperatorSchemaSql exports the Project persistence schema from Drizzle schema", () => {
  const sql = exportOperatorSchemaSql()

  assert.match(sql, /CREATE TABLE [`"]?projects[`"]?/i)
  assert.match(sql, /`key` text NOT NULL/i)
  assert.match(sql, /`repo_path` text NOT NULL/i)
  assert.match(sql, /`repository_package_managers_json` text NOT NULL/i)
  assert.match(sql, /`default_model` text NOT NULL/i)
  assert.match(sql, /`default_reasoning_level` text NOT NULL/i)
  assert.match(sql, /`schedule_enabled` integer NOT NULL/i)
  assert.match(sql, /`next_task_number` integer NOT NULL/i)
  assert.match(
    sql,
    /CREATE UNIQUE INDEX [`"]?projects_active_key_unique[`"]? ON [`"]?projects[`"]? \([`"]?key[`"]?\) WHERE/i
  )
  assert.match(
    sql,
    /CREATE UNIQUE INDEX [`"]?projects_active_repo_path_unique[`"]? ON [`"]?projects[`"]? \([`"]?repo_path[`"]?\) WHERE/i
  )
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
