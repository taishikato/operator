import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { readExistingDatabaseState } from "./existing-database-state.ts"

test("readExistingDatabaseState reports missing marker and tables for a foreign database", async () => {
  const databasePath = await createDatabase(async (client) => {
    await runSql(client, "CREATE TABLE external_table (id text PRIMARY KEY);")
  })

  assert.deepEqual(await readExistingDatabaseState(databasePath), {
    hasInitializationMarker: false,
    hasRequiredOperatorTables: false,
  })
})

test("readExistingDatabaseState reports missing required tables for an initialized legacy database", async () => {
  const databasePath = await createDatabase(async (client) => {
    await runSql(
      client,
      `
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
INSERT INTO operator_metadata (key, value, updated_at)
VALUES ('schema_initialized', 'true', '2026-05-31T00:00:00.000Z');
CREATE TABLE projects (
  id text PRIMARY KEY,
  key text NOT NULL
);
`
    )
  })

  assert.deepEqual(await readExistingDatabaseState(databasePath), {
    hasInitializationMarker: true,
    hasRequiredOperatorTables: false,
  })
})

test("readExistingDatabaseState reports a fully initialized operator database", async () => {
  const databasePath = await createDatabase(async (client) => {
    await runSql(
      client,
      `
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
INSERT INTO operator_metadata (key, value, updated_at)
VALUES ('schema_initialized', 'true', '2026-05-31T00:00:00.000Z');
CREATE TABLE projects (
  id text PRIMARY KEY,
  key text NOT NULL
);
CREATE TABLE tasks (
  id text PRIMARY KEY,
  project_id text NOT NULL
);
`
    )
  })

  assert.deepEqual(await readExistingDatabaseState(databasePath), {
    hasInitializationMarker: true,
    hasRequiredOperatorTables: true,
  })
})

async function createDatabase(
  setup: (client: Awaited<ReturnType<typeof connect>>) => Promise<void>
) {
  const directory = await mkdtemp(join(tmpdir(), "operator-existing-db-state-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await setup(client)
  } finally {
    await client.close()
  }

  return databasePath
}

async function runSql(
  client: Awaited<ReturnType<typeof connect>>,
  sql: string
) {
  await client.exec(sql)
}
