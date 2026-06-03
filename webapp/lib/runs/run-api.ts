import type { AppDataPaths } from "../app-data/app-data.ts"
import { createRunRepository } from "./run-repository.ts"

export type RunApiOptions = {
  databasePath: string
  appDataPaths: AppDataPaths
  runId: string
}

export async function handleGetRunRequest(
  _request: Request,
  options: RunApiOptions
) {
  const detail = await createRunRepository({
    databasePath: options.databasePath,
    appDataPaths: options.appDataPaths,
  }).getRunDetail(options.runId)

  if (!detail) {
    return Response.json(
      { error: { code: "run_not_found", message: "Run not found" } },
      { status: 404 }
    )
  }

  return Response.json({
    run: detail.run,
    rawLogText: detail.rawLogText,
    shouldPoll: detail.shouldPoll,
  })
}
