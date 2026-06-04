import { ArrowLeft } from "lucide-react"
import { notFound } from "next/navigation"

import packageJson from "@/package.json"
import { SchemaWarning } from "@/components/projects/schema-warning"
import { ProjectSettingsPanel } from "@/components/settings/project-settings-panel"
import { resolveAppDataPaths } from "@/lib/app-data/app-data"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import { getAppOperationalStatus } from "@/lib/settings/app-operational-status"

export const dynamic = "force-dynamic"

export default async function ProjectSettingsPage({
  params,
}: {
  params: Promise<{ projectKey: string }>
}) {
  const { projectKey } = await params
  const { databasePath, databaseStatus } = await resolveAddProjectApiOptions()

  if (databaseStatus === "requires_explicit_apply") {
    return (
      <main className="min-h-svh bg-background">
        <header className="border-b px-4 py-4 sm:px-6 lg:px-8">
          <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs font-medium uppercase text-muted-foreground">
                Project {projectKey}
              </p>
              <h1 className="truncate text-xl font-semibold tracking-normal">
                Settings
              </h1>
            </div>
            <a
              href={`/projects/${encodeURIComponent(projectKey)}`}
              className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
            >
              <ArrowLeft className="h-4 w-4" />
              Back to board
            </a>
          </div>
        </header>

        <section className="mx-auto max-w-5xl px-4 py-5 sm:px-6 lg:px-8">
          <SchemaWarning />
        </section>
      </main>
    )
  }

  const project = await createProjectRepository({
    databasePath,
  }).getActiveProjectByKey(projectKey)

  if (!project) {
    notFound()
  }

  const appDataPaths = resolveAppDataPaths({})

  return (
    <main className="min-h-svh bg-background">
      <header className="border-b px-4 py-4 sm:px-6 lg:px-8">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-medium uppercase text-muted-foreground">
              Project {project.key}
            </p>
            <h1 className="truncate text-xl font-semibold tracking-normal">
              Settings
            </h1>
            <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
              {project.repoPath}
            </p>
          </div>
          <a
            href={`/projects/${encodeURIComponent(project.key)}`}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to board
          </a>
        </div>
      </header>

      <section className="mx-auto max-w-5xl px-4 py-5 sm:px-6 lg:px-8">
        <ProjectSettingsPanel
          projectKey={project.key}
          project={{
            defaults: project.defaults,
            schedule: {
              enabled: project.schedule.enabled,
              dailyTime: project.schedule.dailyTime,
              timezone: project.schedule.timezone,
              scheduledRunLimit: project.schedule.scheduledRunLimit,
            },
          }}
          appStatus={getAppOperationalStatus({
            appDataDir: appDataPaths.appDataDir,
            version: packageJson.version,
          })}
        />
      </section>
    </main>
  )
}
