import { notFound } from "next/navigation"

import { RawLogViewer } from "@/components/runs/raw-log-viewer"
import { resolveAppDataPaths } from "@/lib/app-data/app-data"
import { bootstrapLocalDatabase } from "@/lib/db/local-database"
import { createRunRepository } from "@/lib/runs/run-repository"

export const dynamic = "force-dynamic"

export default async function RunDetailPage({
  params,
}: {
  params: Promise<{ runId: string }>
}) {
  const { runId } = await params
  const appDataPaths = resolveAppDataPaths({})
  const database = await bootstrapLocalDatabase(appDataPaths)

  if (database.status === "requires_explicit_apply") {
    return (
      <main className="min-h-svh bg-background px-4 py-5 sm:px-6 lg:px-8">
        <div
          role="alert"
          className="mx-auto max-w-7xl rounded-md border border-amber-500/35 bg-amber-500/10 p-4 text-sm text-amber-950 dark:text-amber-100"
        >
          Operator database schema is out of date. Run the explicit database
          apply command or reset the local Operator database.
        </div>
      </main>
    )
  }

  const detail = await createRunRepository({
    databasePath: database.databasePath,
    appDataPaths,
  }).getRunDetail(runId)

  if (!detail) {
    notFound()
  }

  return (
    <main className="min-h-svh bg-background">
      <header className="border-b px-4 py-4 sm:px-6 lg:px-8">
        <div className="mx-auto max-w-7xl">
          <p className="font-mono text-xs text-muted-foreground">
            {detail.run.taskDisplayId}
          </p>
          <h1 className="mt-1 text-xl font-semibold tracking-normal">
            Raw run log
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {detail.run.status}
          </p>
        </div>
      </header>

      <section className="mx-auto max-w-7xl px-4 py-5 sm:px-6 lg:px-8">
        <RawLogViewer
          runId={detail.run.id}
          initialStatus={detail.run.status}
          initialRawLogText={detail.rawLogText}
        />
      </section>
    </main>
  )
}
