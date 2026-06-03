import { connect } from "@tursodatabase/database"
import { desc, eq, inArray } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { readFile } from "node:fs/promises"

import { resolveRunLogPath, type AppDataPaths } from "../app-data/app-data.ts"
import { runs } from "../db/schema.ts"
import { readRunLogLines, type StoredRunLogEvent } from "./raw-log.ts"
export { shouldPollRunLog } from "./run-status.ts"
import { shouldPollRunLog } from "./run-status.ts"

export type RunSummary = {
  id: string
  taskId: string
  taskDisplayId: string
  status: string
  blockedReason: string | null
  taskBranchName: string
  model: string
  reasoningLevel: string
  rawLogKey: string
  startedAt: string
  finishedAt: string | null
  updatedAt: string
}

export type RunDetail = {
  run: RunSummary
  lines: StoredRunLogEvent[]
  rawLogText: string
  shouldPoll: boolean
}

export type LatestRunSummary = Pick<
  RunSummary,
  "id" | "status" | "blockedReason" | "startedAt" | "finishedAt" | "updatedAt"
> & {
  rawLogPath: string
}

type RunDb = ReturnType<typeof drizzle<{ runs: typeof runs }>>

export function createRunRepository({
  databasePath,
  appDataPaths,
}: {
  databasePath: string
  appDataPaths: AppDataPaths
}) {
  return {
    async getRunDetail(runId: string): Promise<RunDetail | null> {
      const run = await selectRun(databasePath, runId)

      if (!run) {
        return null
      }

      return {
        run,
        lines: await readRunLogLines(appDataPaths, run.rawLogKey),
        rawLogText: await readRawLogText(appDataPaths, run.rawLogKey),
        shouldPoll: shouldPollRunLog(run.status),
      }
    },

    async listLatestRunSummariesForTasks(taskIds: string[]) {
      if (taskIds.length === 0) {
        return {}
      }

      return withRunDb(databasePath, async (db) => {
        const rows = await db
          .select()
          .from(runs)
          .where(inArray(runs.taskId, taskIds))
          .orderBy(desc(runs.startedAt))
        const summaries: Record<string, LatestRunSummary> = {}

        for (const row of rows) {
          if (summaries[row.taskId]) {
            continue
          }

          summaries[row.taskId] = {
            id: row.id,
            status: row.status,
            blockedReason: row.blockedReason,
            startedAt: row.startedAt,
            finishedAt: row.finishedAt,
            updatedAt: row.updatedAt,
            rawLogPath: `/runs/${encodeURIComponent(row.id)}`,
          }
        }

        return summaries
      })
    },
  }
}

async function selectRun(databasePath: string, runId: string) {
  return withRunDb(databasePath, async (db) => {
    const [run] = await db
      .select()
      .from(runs)
      .where(eq(runs.id, runId))
      .limit(1)

    return run ? toRunSummary(run) : null
  })
}

async function readRawLogText(paths: AppDataPaths, logKey: string) {
  try {
    return await readFile(resolveRunLogPath(paths, logKey), "utf8")
  } catch (error) {
    if (isFileNotFoundError(error)) {
      return ""
    }

    throw error
  }
}

function toRunSummary(row: typeof runs.$inferSelect): RunSummary {
  return {
    id: row.id,
    taskId: row.taskId,
    taskDisplayId: row.taskDisplayId,
    status: row.status,
    blockedReason: row.blockedReason,
    taskBranchName: row.taskBranchName,
    model: row.model,
    reasoningLevel: row.reasoningLevel,
    rawLogKey: row.rawLogKey,
    startedAt: row.startedAt,
    finishedAt: row.finishedAt,
    updatedAt: row.updatedAt,
  }
}

async function withRunDb<T>(
  databasePath: string,
  callback: (db: RunDb) => Promise<T>
) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { runs } })

  try {
    return await callback(db)
  } finally {
    await client.close()
  }
}

function isFileNotFoundError(error: unknown) {
  return (
    error instanceof Error &&
    "code" in error &&
    (error as NodeJS.ErrnoException).code === "ENOENT"
  )
}
