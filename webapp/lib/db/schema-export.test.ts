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
  assert.match(sql, /`last_scheduled_local_date` text/i)
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

test("exportOperatorSchemaSql exports the Task persistence schema from Drizzle schema", () => {
  const sql = exportOperatorSchemaSql()

  assert.match(sql, /CREATE TABLE [`"]?tasks[`"]?/i)
  assert.match(sql, /`project_id` text NOT NULL/i)
  assert.match(sql, /`number` integer NOT NULL/i)
  assert.match(sql, /`display_id` text NOT NULL/i)
  assert.match(sql, /`title` text NOT NULL/i)
  assert.match(sql, /`body_markdown` text NOT NULL/i)
  assert.match(sql, /`acceptance_criteria_markdown` text NOT NULL/i)
  assert.match(sql, /`status` text NOT NULL/i)
  assert.match(sql, /`position` integer NOT NULL/i)
  assert.match(sql, /`task_branch_name` text/i)
  assert.match(sql, /`pull_request_url` text/i)
  assert.match(sql, /`pull_request_error` text/i)
  assert.match(sql, /`blocked_reason` text/i)
  assert.match(sql, /`archived_at` text/i)
  assert.match(
    sql,
    /CREATE UNIQUE INDEX [`"]?tasks_project_number_unique[`"]? ON [`"]?tasks[`"]? \([`"]?project_id[`"]?,\s*[`"]?number[`"]?\)/i
  )
  assert.match(
    sql,
    /CREATE UNIQUE INDEX [`"]?tasks_display_id_unique[`"]? ON [`"]?tasks[`"]? \([`"]?display_id[`"]?\)/i
  )
})

test("exportOperatorSchemaSql exports the Run persistence schema from Drizzle schema", () => {
  const sql = exportOperatorSchemaSql()

  assert.match(sql, /CREATE TABLE [`"]?runs[`"]?/i)
  assert.match(sql, /`project_id` text NOT NULL/i)
  assert.match(sql, /`task_id` text NOT NULL/i)
  assert.match(sql, /`task_display_id` text NOT NULL/i)
  assert.match(sql, /`task_branch_name` text NOT NULL/i)
  assert.match(sql, /`model` text NOT NULL/i)
  assert.match(sql, /`reasoning_level` text NOT NULL/i)
  assert.match(sql, /`head_before` text NOT NULL/i)
  assert.match(sql, /`head_after` text/i)
  assert.match(sql, /`worktree_dirty_before` integer NOT NULL/i)
  assert.match(sql, /`worktree_dirty_after` integer/i)
  assert.match(sql, /`adapter_run_id` text/i)
  assert.match(sql, /`raw_log_key` text NOT NULL/i)
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
