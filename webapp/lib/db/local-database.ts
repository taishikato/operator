import { connect } from "@tursodatabase/database"
import { stat } from "node:fs/promises"

import { ensureAppData, type AppDataPaths } from "../app-data/app-data.ts"
import { applyOperatorSchemaWithAtlas } from "./schema-apply.ts"
import { exportOperatorSchemaSql } from "./schema-export.ts"

export type BootstrapLocalDatabaseResult = {
  databasePath: string
  schemaApplied: boolean
  status: "initialized" | "ready" | "requires_explicit_apply"
}

export type ApplyLocalDatabaseSchemaResult = {
  databasePath: string
  schemaApplied: true
  status: "applied"
}

export type SchemaApplyOptions = {
  databasePath: string
  schemaSql: string
}

export type BootstrapLocalDatabaseOptions = {
  applySchema: (options: SchemaApplyOptions) => void | Promise<void>
  exportSchemaSql: () => string | Promise<string>
}

export async function bootstrapLocalDatabase(
  paths: AppDataPaths,
  options: BootstrapLocalDatabaseOptions = defaultSchemaOptions
): Promise<BootstrapLocalDatabaseResult> {
  await ensureAppData(paths)

  const fileState = await readDatabaseFileState(paths.databasePath)

  if (fileState === "existing") {
    if (!(await hasInitializationMarker(paths.databasePath))) {
      return {
        databasePath: paths.databasePath,
        schemaApplied: false,
        status: "requires_explicit_apply",
      }
    }

    return {
      databasePath: paths.databasePath,
      schemaApplied: false,
      status: "ready",
    }
  }

  await applySchemaAndMarkInitialized(paths, options)

  return {
    databasePath: paths.databasePath,
    schemaApplied: true,
    status: "initialized",
  }
}

export async function applyLocalDatabaseSchema(
  paths: AppDataPaths,
  options: BootstrapLocalDatabaseOptions = defaultSchemaOptions
): Promise<ApplyLocalDatabaseSchemaResult> {
  await ensureAppData(paths)
  await applySchemaAndMarkInitialized(paths, options)

  return {
    databasePath: paths.databasePath,
    schemaApplied: true,
    status: "applied",
  }
}

const defaultSchemaOptions = {
  applySchema: applyOperatorSchemaWithAtlas,
  exportSchemaSql: exportOperatorSchemaSql,
} satisfies BootstrapLocalDatabaseOptions

async function applySchemaAndMarkInitialized(
  paths: AppDataPaths,
  options: BootstrapLocalDatabaseOptions
) {
  const schemaSql = await options.exportSchemaSql()
  await options.applySchema({ databasePath: paths.databasePath, schemaSql })
  await markDatabaseInitialized(paths.databasePath)
}

async function markDatabaseInitialized(databasePath: string) {
  const client = await connect(databasePath)

  try {
    await client.run(
      `INSERT OR REPLACE INTO operator_metadata (key, value, updated_at)
       VALUES (?, ?, ?)`,
      "schema_initialized",
      "true",
      new Date().toISOString()
    )
  } finally {
    await client.close()
  }
}

async function hasInitializationMarker(databasePath: string) {
  const client = await connect(databasePath)

  try {
    const row = await client.get(
      "SELECT value FROM operator_metadata WHERE key = ?",
      "schema_initialized"
    )

    return row?.value === "true"
  } catch (error) {
    if (isMissingMetadataTableError(error)) {
      return false
    }

    throw error
  } finally {
    await client.close()
  }
}

function isMissingMetadataTableError(error: unknown) {
  return (
    error instanceof Error &&
    error.message.includes("no such table: operator_metadata")
  )
}

async function readDatabaseFileState(path: string) {
  try {
    const stats = await stat(path)
    return stats.size === 0 ? "uninitialized" : "existing"
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return "missing"
    }
    throw error
  }
}
