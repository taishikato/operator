import assert from "node:assert/strict"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import {
  applySpikeSchemaWithAtlas,
  isAtlasAvailable,
} from "./atlas-spike.ts"
import { exportSpikeProjectsSql } from "./export-spike-schema.ts"
import {
  insertAndSelectSpikeProject,
  runTursoDrizzleCompatibilitySpike,
} from "./turso-drizzle-spike.ts"

test("drizzle-kit export defines spike_projects from schema.ts", () => {
  const sql = exportSpikeProjectsSql()

  assert.match(sql, /CREATE TABLE [`"]?spike_projects[`"]?/i)
  assert.match(sql, /`id` text PRIMARY KEY/i)
  assert.match(sql, /`repo_path` text NOT NULL UNIQUE/i)
})

test("Turso local storage can create and query a table using drizzle-kit export DDL", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-spike-"))

  try {
    const exportedSql = exportSpikeProjectsSql()
    const result = await runTursoDrizzleCompatibilitySpike({
      databasePath: join(directory, "operator.db"),
      createTableSql: exportedSql,
    })

    assert.deepEqual(result, {
      databaseCreated: true,
      project: {
        id: "project_01",
        key: "OP",
        name: "Operator",
        repoPath: "/tmp/operator",
      },
    })
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})

test(
  "Atlas declarative apply can create spike_projects from drizzle-kit export",
  async (t) => {
    if (!isAtlasAvailable()) {
      t.skip("Atlas CLI is not installed")
    }

    const directory = await mkdtemp(join(tmpdir(), "operator-atlas-spike-"))

    try {
      const databasePath = join(directory, "operator.db")
      const schemaSqlPath = join(directory, "schema.sql")
      await writeFile(schemaSqlPath, exportSpikeProjectsSql(), "utf8")

      applySpikeSchemaWithAtlas({ databasePath, schemaSqlPath })

      const project = await insertAndSelectSpikeProject(databasePath)

      assert.deepEqual(project, {
        id: "project_01",
        key: "OP",
        name: "Operator",
        repoPath: "/tmp/operator",
      })
    } finally {
      await rm(directory, { recursive: true, force: true })
    }
  },
)
