import { connect } from "@tursodatabase/database"
import { stat } from "node:fs/promises"

import { ensureAppData, type AppDataPaths } from "../app-data/app-data.ts"
import { readExistingDatabaseState } from "./existing-database-state.ts"
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
  autoApprove?: boolean
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
    const existingState = await readExistingDatabaseState(paths.databasePath)

    if (
      !existingState.hasInitializationMarker ||
      !existingState.hasRequiredOperatorTables ||
      !existingState.hasRequiredOperatorColumns
    ) {
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

  await applySchemaAndMarkInitialized(paths, options, { autoApprove: true })

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
  await applySchemaAndMarkInitialized(paths, options, { autoApprove: true })

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
  options: BootstrapLocalDatabaseOptions,
  { autoApprove }: { autoApprove: boolean }
) {
  const schemaSql = await options.exportSchemaSql()
  await options.applySchema({
    autoApprove,
    databasePath: paths.databasePath,
    schemaSql,
  })
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
