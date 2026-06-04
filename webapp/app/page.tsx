import { Plus } from "lucide-react"
import Link from "next/link"

import { AddProjectForm } from "@/components/projects/add-project-form"
import { SchemaWarning } from "@/components/projects/schema-warning"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import type { Project } from "@/lib/projects/project-repository"

export const dynamic = "force-dynamic"

export default async function Page() {
  const { databasePath, databaseStatus } = await resolveAddProjectApiOptions()

  if (databaseStatus === "requires_explicit_apply") {
    return (
      <main className="min-h-svh bg-background px-4 py-6 sm:px-6 lg:px-8">
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
          <ProjectHomeHeader />
          <SchemaWarning />
        </div>
      </main>
    )
  }

  const projects = await createProjectRepository({
    databasePath,
  }).listActiveProjects()

  return (
    <main className="min-h-svh bg-background px-4 py-6 sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
        {projects.length === 0 ? (
          <>
            <ProjectHomeHeader description="Add a local Git repository to create the first Project workspace." />
            <AddProjectForm />
          </>
        ) : (
          <>
            <div className="flex flex-wrap items-start justify-between gap-3 border-b pb-4">
              <ProjectHomeHeader description="Choose a local Git repository workspace." />
              <Link
                href="/projects/new"
                className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
              >
                <Plus className="h-4 w-4" />
                Add Project
              </Link>
            </div>
            <ProjectList projects={projects} />
          </>
        )}
      </div>
    </main>
  )
}

function ProjectHomeHeader({ description }: { description?: string }) {
  return (
    <header className="flex min-w-0 flex-col gap-1">
      <p className="text-sm font-medium text-muted-foreground">Operator</p>
      <h1 className="text-xl font-semibold tracking-normal">Projects</h1>
      {description ? (
        <p className="max-w-3xl text-sm text-muted-foreground">
          {description}
        </p>
      ) : null}
    </header>
  )
}

function ProjectList({ projects }: { projects: Project[] }) {
  return (
    <section className="grid gap-3">
      {projects.map((project) => (
        <article
          key={project.id}
          className="flex flex-wrap items-center justify-between gap-3 rounded-lg border bg-card p-4 shadow-sm"
        >
          <div className="min-w-0">
            <p className="text-xs font-medium text-muted-foreground uppercase">
              Project {project.key}
            </p>
            <h2 className="truncate text-lg font-semibold tracking-normal">
              {project.displayName}
            </h2>
            <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
              {project.repoPath}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <div className="rounded-md border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
              Schedule {project.schedule.enabled ? "on" : "off"}
            </div>
            <Link
              href={`/projects/${encodeURIComponent(project.key)}`}
              aria-label={`Open ${project.displayName}`}
              className="inline-flex h-8 items-center rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
            >
              Open
            </Link>
          </div>
        </article>
      ))}
    </section>
  )
}
