import { resolveAppDataPaths } from "../app-data/app-data.ts"
import { bootstrapLocalDatabase } from "./local-database.ts"

export type LocalDatabaseOptions = {
  databasePath: string
  databaseStatus: "initialized" | "ready" | "requires_explicit_apply"
}

export async function resolveLocalDatabaseOptions(): Promise<LocalDatabaseOptions> {
  const result = await bootstrapLocalDatabase(resolveAppDataPaths({}))

  return { databasePath: result.databasePath, databaseStatus: result.status }
}
