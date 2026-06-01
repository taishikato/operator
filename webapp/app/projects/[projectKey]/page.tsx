import { notFound } from "next/navigation"

import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"

export const dynamic = "force-dynamic"

const KANBAN_COLUMNS = ["Backlog", "Ready", "Running", "Review", "Done", "Blocked"]

export default async function ProjectPage({
  params,
}: {
  params: Promise<{ projectKey: string }>
}) {
  const { projectKey } = await params
  const { databasePath } = await resolveAddProjectApiOptions()
  const project = await createProjectRepository({
    databasePath,
  }).getActiveProjectByKey(projectKey)

  if (!project) {
    notFound()
  }

  return (
    <main className="min-h-svh bg-background">
      <header className="border-b px-4 py-4 sm:px-6 lg:px-8">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-medium uppercase text-muted-foreground">
              Project {project.key}
            </p>
            <h1 className="truncate text-xl font-semibold tracking-normal">
              {project.displayName}
            </h1>
            <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
              {project.repoPath}
            </p>
          </div>
          <div className="rounded-md border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
            Schedule off
          </div>
        </div>
      </header>

      <section className="mx-auto grid max-w-7xl gap-4 px-4 py-5 sm:px-6 lg:grid-cols-6 lg:px-8">
        {KANBAN_COLUMNS.map((column) => (
          <div
            key={column}
            className="min-h-48 rounded-lg border bg-card p-3 shadow-sm"
          >
            <div className="flex items-center justify-between gap-2">
              <h2 className="text-sm font-semibold">{column}</h2>
              <span className="rounded-full border px-2 py-0.5 text-xs text-muted-foreground">
                0
              </span>
            </div>
            <div className="mt-4 rounded-md border border-dashed bg-muted/25 p-3 text-xs text-muted-foreground">
              No tasks yet.
            </div>
          </div>
        ))}
      </section>
    </main>
  )
}
