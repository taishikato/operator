import { dirname } from "node:path"

import { resolveAppDataPaths } from "../app-data/app-data.ts"
import {
  bootstrapLocalDatabase,
  type BootstrapLocalDatabaseResult,
} from "../db/local-database.ts"
import { ensureStaleRunsReconciled } from "../runs/run-orchestration.ts"
import { ensureProjectSchedulerRuntimeStarted } from "../scheduler/project-scheduler-runtime.ts"
import { shouldStartSchedulerFromWebRequest } from "./operator-runtime-env.ts"

export type CliManagedServerRuntimeDependencies = {
  bootstrapDatabase: () => Promise<BootstrapLocalDatabaseResult>
  env: Partial<NodeJS.ProcessEnv>
  reconcileStaleRuns: (
    databasePath: string
  ) => Promise<{ interruptedRuns: number }>
  startScheduler: (input: { databasePath: string }) => unknown
}

let runtimeStarted = false

export async function startCliManagedServerRuntime(
  dependencies = createDefaultCliManagedServerRuntimeDependencies()
) {
  if (shouldStartSchedulerFromWebRequest(dependencies.env)) {
    return
  }

  if (runtimeStarted) {
    return
  }

  const database = await dependencies.bootstrapDatabase()
  await dependencies.reconcileStaleRuns(database.databasePath)
  dependencies.startScheduler({ databasePath: database.databasePath })
  runtimeStarted = true
}

export function resetCliManagedServerRuntimeForTests() {
  runtimeStarted = false
}

function createDefaultCliManagedServerRuntimeDependencies(): CliManagedServerRuntimeDependencies {
  const paths = resolveAppDataPaths({
    appDataRoot: process.env.OPERATOR_DATABASE_PATH
      ? dirname(process.env.OPERATOR_DATABASE_PATH)
      : undefined,
  })

  return {
    bootstrapDatabase: () => bootstrapLocalDatabase(paths),
    env: process.env,
    reconcileStaleRuns: ensureStaleRunsReconciled,
    startScheduler: ({ databasePath }) =>
      ensureProjectSchedulerRuntimeStarted({ databasePath }),
  }
}
