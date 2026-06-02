import { connect } from "@tursodatabase/database"

import { getRequiredOperatorTableNames } from "./required-operator-tables.ts"

export type ExistingDatabaseState = {
  hasInitializationMarker: boolean
  hasRequiredOperatorTables: boolean
}

export async function readExistingDatabaseState(
  databasePath: string
): Promise<ExistingDatabaseState> {
  const client = await connect(databasePath)

  try {
    const hasInitializationMarker = await readInitializationMarker(client)
    const hasRequiredOperatorTables =
      await readRequiredOperatorTables(client)

    return { hasInitializationMarker, hasRequiredOperatorTables }
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

function isMissingMetadataTableError(error: unknown) {
  return (
    error instanceof Error &&
    error.message.includes("no such table: operator_metadata")
  )
}
