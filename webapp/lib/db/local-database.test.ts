import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdir, mkdtemp, stat, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import {
  applyLocalDatabaseSchema,
  bootstrapLocalDatabase,
} from "./local-database.ts"
import { isAtlasAvailable } from "./schema-apply.ts"

const schemaSql = `
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
`

test("bootstrapLocalDatabase applies schema and creates storage on first initialization", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  const applyCalls: Array<{ databasePath: string; schemaSql: string }> = []

  const result = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => schemaSql,
    applySchema: async ({ databasePath, schemaSql }) => {
      applyCalls.push({ databasePath, schemaSql })
      const client = await connect(databasePath)

      try {
        await client.exec(schemaSql)
      } finally {
        await client.close()
      }
    },
  })

  assert.equal(result.status, "initialized")
  assert.equal(result.schemaApplied, true)
  assert.deepEqual(applyCalls, [
    { databasePath: paths.databasePath, schemaSql },
  ])
  assert.equal((await stat(paths.appDataDir)).isDirectory(), true)
  assert.equal((await stat(paths.runLogsDir)).isDirectory(), true)
  assert.equal((await stat(paths.databasePath)).isFile(), true)
})

test("bootstrapLocalDatabase does not auto-apply schema for an initialized database", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  let applyCount = 0

  await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => schemaSql,
    applySchema: async ({ databasePath, schemaSql }) => {
      applyCount += 1
      const client = await connect(databasePath)

      try {
        await client.exec(schemaSql)
      } finally {
        await client.close()
      }
    },
  })

  const result = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => {
      throw new Error("schema export should be explicit for existing DBs")
    },
    applySchema: () => {
      throw new Error("schema apply should be explicit for existing DBs")
    },
  })

  assert.equal(applyCount, 1)
  assert.deepEqual(result, {
    databasePath: paths.databasePath,
    schemaApplied: false,
    status: "ready",
  })
})

test("bootstrapLocalDatabase applies schema for an empty uninitialized database file", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })
  await writeFile(paths.databasePath, "")
  let applyCount = 0

  const result = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => schemaSql,
    applySchema: async ({ databasePath, schemaSql }) => {
      applyCount += 1
      const client = await connect(databasePath)

      try {
        await client.exec(schemaSql)
      } finally {
        await client.close()
      }
    },
  })

  assert.equal(result.status, "initialized")
  assert.equal(result.schemaApplied, true)
  assert.equal(applyCount, 1)
})

test("bootstrapLocalDatabase requires explicit apply for a non-empty database without the initialization marker", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })

  const client = await connect(paths.databasePath)
  try {
    await client.exec("CREATE TABLE external_table (id text PRIMARY KEY);")
  } finally {
    await client.close()
  }

  const result = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => {
      throw new Error("schema export should be explicit for existing DBs")
    },
    applySchema: () => {
      throw new Error("schema apply should be explicit for existing DBs")
    },
  })

  assert.deepEqual(result, {
    databasePath: paths.databasePath,
    schemaApplied: false,
    status: "requires_explicit_apply",
  })
})

test("applyLocalDatabaseSchema provides the explicit schema update path for existing databases", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => schemaSql,
    applySchema: async ({ databasePath, schemaSql }) => {
      const client = await connect(databasePath)

      try {
        await client.exec(schemaSql)
      } finally {
        await client.close()
      }
    },
  })

  const explicitSchemaSql = `
CREATE TABLE IF NOT EXISTS operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
CREATE TABLE explicit_apply_probe (id text PRIMARY KEY);
`
  const applyCalls: Array<{ databasePath: string; schemaSql: string }> = []

  const result = await applyLocalDatabaseSchema(paths, {
    exportSchemaSql: () => explicitSchemaSql,
    applySchema: async ({ databasePath, schemaSql }) => {
      applyCalls.push({ databasePath, schemaSql })
      const client = await connect(databasePath)

      try {
        await client.exec(schemaSql)
      } finally {
        await client.close()
      }
    },
  })

  assert.deepEqual(result, {
    databasePath: paths.databasePath,
    schemaApplied: true,
    status: "applied",
  })
  assert.deepEqual(applyCalls, [
    { databasePath: paths.databasePath, schemaSql: explicitSchemaSql },
  ])
})

test("bootstrapLocalDatabase default path initializes through Drizzle export and Atlas apply", async (t) => {
  if (!isAtlasAvailable()) {
    t.skip("Atlas CLI is not installed")
    return
  }

  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })

  const result = await bootstrapLocalDatabase(paths)

  assert.equal(result.status, "initialized")
  assert.equal(result.schemaApplied, true)
  assert.equal((await stat(paths.databasePath)).isFile(), true)
})

test("bootstrapLocalDatabase default path supports app data directories with spaces", async (t) => {
  if (!isAtlasAvailable()) {
    t.skip("Atlas CLI is not installed")
    return
  }

  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "Application Support", "Operator"),
  })

  const result = await bootstrapLocalDatabase(paths)

  assert.equal(result.status, "initialized")
  assert.equal(result.schemaApplied, true)
  assert.equal((await stat(paths.databasePath)).isFile(), true)
})
