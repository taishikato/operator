import { connect } from "@tursodatabase/database"
import { getTableColumns, getTableName } from "drizzle-orm"

import { getRequiredOperatorTableNames } from "./required-operator-tables.ts"
import { operatorSchemaTables } from "./schema.ts"

export type ExistingDatabaseState = {
  hasInitializationMarker: boolean
  hasRequiredOperatorTables: boolean
  hasRequiredOperatorColumns: boolean
}

export async function readExistingDatabaseState(
  databasePath: string
): Promise<ExistingDatabaseState> {
  const client = await connect(databasePath)

  try {
    const hasInitializationMarker = await readInitializationMarker(client)
    const hasRequiredOperatorTables =
      await readRequiredOperatorTables(client)
    const hasRequiredOperatorColumns = hasRequiredOperatorTables
      ? await readRequiredOperatorColumns(client)
      : false

    return {
      hasInitializationMarker,
      hasRequiredOperatorTables,
      hasRequiredOperatorColumns,
    }
  } finally {
    await client.close()
  }
}

async function readInitializationMarker(
  client: Awaited<ReturnType<typeof connect>>
) {
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
  }
}

async function readRequiredOperatorTables(
  client: Awaited<ReturnType<typeof connect>>
) {
  const requiredTableNames = getRequiredOperatorTableNames()
  const placeholders = requiredTableNames.map(() => "?").join(", ")
  const rows = await client.all(
    `SELECT name FROM sqlite_master
     WHERE type = 'table' AND name IN (${placeholders})`,
    ...requiredTableNames
  )
  const tableNames = new Set(
    rows
      .map((row) => row.name)
      .filter((name): name is string => typeof name === "string")
  )

  return requiredTableNames.every((name) => tableNames.has(name))
}

async function readRequiredOperatorColumns(
  client: Awaited<ReturnType<typeof connect>>
) {
  for (const table of operatorSchemaTables) {
    const tableName = getTableName(table)
    const requiredColumnNames = Object.values(getTableColumns(table)).map(
      (column) => column.name
    )
    const rows = await client.all(
      `PRAGMA table_info(${quoteSqlIdentifier(tableName)})`
    )
    const columnNames = new Set(
      rows
        .map((row) => row.name)
        .filter((name): name is string => typeof name === "string")
    )

    if (!requiredColumnNames.every((name) => columnNames.has(name))) {
      return false
    }
  }

  return true
}

function quoteSqlIdentifier(identifier: string) {
  return `"${identifier.replaceAll('"', '""')}"`
}

function isMissingMetadataTableError(error: unknown) {
  return (
    error instanceof Error &&
    error.message.includes("no such table: operator_metadata")
  )
}
