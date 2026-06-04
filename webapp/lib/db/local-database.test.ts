import { connect } from "@tursodatabase/database"
import assert from "node:assert/strict"
import { mkdir, mkdtemp, stat, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { readExistingDatabaseState } from "./existing-database-state.ts"
import {
  applyLocalDatabaseSchema,
  bootstrapLocalDatabase,
} from "./local-database.ts"
import { isAtlasAvailable } from "./schema-apply.ts"
import { exportOperatorSchemaSql } from "./schema-export.ts"

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
  const applyCalls: Array<{
    autoApprove?: boolean
    databasePath: string
    schemaSql: string
  }> = []

  const result = await bootstrapLocalDatabase(paths, {
    exportSchemaSql: () => schemaSql,
    applySchema: async ({ autoApprove, databasePath, schemaSql }) => {
      applyCalls.push({ autoApprove, databasePath, schemaSql })
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
    { autoApprove: true, databasePath: paths.databasePath, schemaSql },
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
    exportSchemaSql: exportOperatorSchemaSql,
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

test("bootstrapLocalDatabase requires explicit apply for an initialized database missing a required table", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })

  const client = await connect(paths.databasePath)
  try {
    await client.exec(`
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
`)
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

test("bootstrapLocalDatabase requires explicit apply for an initialized database missing a required run column", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })

  const client = await connect(paths.databasePath)
  try {
    await client.exec(`
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
CREATE TABLE runs (
  id text PRIMARY KEY,
  task_id text NOT NULL
);
`)
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
  const applyCalls: Array<{
    autoApprove?: boolean
    databasePath: string
    schemaSql: string
  }> = []

  const result = await applyLocalDatabaseSchema(paths, {
    exportSchemaSql: () => explicitSchemaSql,
    applySchema: async ({ autoApprove, databasePath, schemaSql }) => {
      applyCalls.push({ autoApprove, databasePath, schemaSql })
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
    {
      autoApprove: true,
      databasePath: paths.databasePath,
      schemaSql: explicitSchemaSql,
    },
  ])
})

test("applyLocalDatabaseSchema default path applies Atlas plans non-interactively for old Operator databases", async (t) => {
  if (!isAtlasAvailable()) {
    t.skip("Atlas CLI is not installed")
    return
  }

  const directory = await mkdtemp(join(tmpdir(), "operator-db-bootstrap-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "app-data"),
  })
  await mkdir(paths.appDataDir, { recursive: true })

  const client = await connect(paths.databasePath)
  try {
    await client.exec(`
CREATE TABLE operator_metadata (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at text NOT NULL
);
INSERT INTO operator_metadata (key, value, updated_at)
VALUES ('schema_initialized', 'true', '2026-05-31T00:00:00.000Z');
CREATE TABLE projects (
  id text PRIMARY KEY,
  key text NOT NULL,
  display_name text NOT NULL,
  repo_path text NOT NULL,
  repository_name text NOT NULL,
  repository_package_managers_json text NOT NULL,
  repository_instruction_files_json text NOT NULL,
  default_model text NOT NULL,
  default_reasoning_level text NOT NULL,
  run_timeout_seconds integer NOT NULL,
  schedule_enabled integer NOT NULL,
  schedule_daily_time text NOT NULL,
  schedule_timezone text NOT NULL,
  scheduled_run_limit integer NOT NULL,
  next_task_number integer NOT NULL,
  created_at text NOT NULL,
  updated_at text NOT NULL
);
CREATE TABLE tasks (
  id text PRIMARY KEY,
  project_id text NOT NULL,
  number integer NOT NULL,
  display_id text NOT NULL,
  title text NOT NULL,
  body_markdown text NOT NULL,
  acceptance_criteria_markdown text NOT NULL,
  status text NOT NULL,
  position integer NOT NULL,
  created_at text NOT NULL,
  updated_at text NOT NULL
);
CREATE TABLE runs (
  id text PRIMARY KEY,
  project_id text NOT NULL,
  task_id text NOT NULL,
  task_display_id text NOT NULL,
  status text NOT NULL,
  task_branch_name text NOT NULL,
  model text NOT NULL,
  reasoning_level text NOT NULL,
  base_branch text NOT NULL,
  head_before text NOT NULL,
  worktree_dirty_before integer NOT NULL,
  started_at text NOT NULL,
  updated_at text NOT NULL
);
`)
  } finally {
    await client.close()
  }

  const result = await applyLocalDatabaseSchema(paths)

  assert.deepEqual(result, {
    databasePath: paths.databasePath,
    schemaApplied: true,
    status: "applied",
  })

  assert.deepEqual(await readExistingDatabaseState(paths.databasePath), {
    hasInitializationMarker: true,
    hasRequiredOperatorColumns: true,
    hasRequiredOperatorTables: true,
  })
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
