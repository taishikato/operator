import { resolveAppDataPaths } from "@/lib/app-data/app-data"
import { bootstrapLocalDatabase } from "@/lib/db/local-database"
import { handleGetRunRequest } from "@/lib/runs/run-api"

export const runtime = "nodejs"

export async function GET(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { runId } = (await params) as { runId: string }
  const appDataPaths = resolveAppDataPaths({})
  const database = await bootstrapLocalDatabase(appDataPaths)

  if (database.status === "requires_explicit_apply") {
    return Response.json(
      {
        error: {
          code: "schema_apply_required",
          message:
            "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database.",
        },
      },
      { status: 503 }
    )
  }

  return handleGetRunRequest(request, {
    databasePath: database.databasePath,
    appDataPaths,
    runId,
  })
}
