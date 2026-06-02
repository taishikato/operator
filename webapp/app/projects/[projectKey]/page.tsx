import { notFound } from "next/navigation"

import { TaskCreateForm } from "@/components/tasks/task-create-form"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import {
  createKanbanColumns,
  resolveTaskDrawer,
  type KanbanTask,
} from "@/lib/tasks/kanban-view"
import { createTaskRepository } from "@/lib/tasks/task-repository"

export const dynamic = "force-dynamic"

export default async function ProjectPage({
  params,
  searchParams,
}: {
  params: Promise<{ projectKey: string }>
  searchParams: Promise<{ task?: string }>
}) {
  const { projectKey } = await params
  const { task: selectedTaskDisplayId } = await searchParams
  const { databasePath, databaseStatus } = await resolveAddProjectApiOptions()
  const project = await createProjectRepository({
    databasePath,
  }).getActiveProjectByKey(projectKey)

  if (!project) {
    notFound()
  }

  if (databaseStatus === "requires_explicit_apply") {
    return (
      <main className="min-h-svh bg-background">
        <ProjectHeader project={project} />
        <section className="mx-auto max-w-7xl px-4 py-5 sm:px-6 lg:px-8">
          <div
            role="alert"
            className="rounded-lg border border-amber-500/35 bg-amber-500/10 p-4 text-sm text-amber-950 dark:text-amber-100"
          >
            Operator database schema is out of date. Run the explicit database
            apply command or reset the local Operator database.
          </div>
        </section>
      </main>
    )
  }

  const tasks = await createTaskRepository({
    databasePath,
  }).listActiveTasksForProject(project.id)
  const kanbanTasks: KanbanTask[] = tasks.map((task) => ({
    id: task.id,
    displayId: task.displayId,
    title: task.title,
    bodyMarkdown: task.bodyMarkdown,
    acceptanceCriteriaMarkdown: task.acceptanceCriteriaMarkdown,
    status: task.status,
    position: task.position,
  }))
  const columns = createKanbanColumns(kanbanTasks)
  const selectedTask = resolveTaskDrawer(selectedTaskDisplayId, kanbanTasks)

  return (
    <main className="min-h-svh bg-background">
      <ProjectHeader project={project} />

      <div className="mx-auto grid max-w-7xl gap-4 px-4 py-5 sm:px-6 lg:grid-cols-[320px_minmax(0,1fr)] lg:px-8">
        <aside className="min-w-0">
          <TaskCreateForm projectKey={project.key} />
        </aside>

        <section className="grid min-w-0 gap-3 md:grid-cols-2 xl:grid-cols-6">
          {columns.map((column) => (
            <div
              key={column.status}
              className="min-h-56 rounded-lg border bg-card p-3 shadow-sm"
            >
              <div className="flex items-center justify-between gap-2">
                <h2 className="text-sm font-semibold">{column.label}</h2>
                <span className="rounded-full border px-2 py-0.5 text-xs text-muted-foreground">
                  {column.tasks.length}
                </span>
              </div>
              <div className="mt-4 grid gap-2">
                {column.tasks.length > 0 ? (
                  column.tasks.map((task) => (
                    <a
                      key={task.id}
                      href={`/projects/${encodeURIComponent(project.key)}?task=${encodeURIComponent(task.displayId)}`}
                      className="block rounded-md border bg-background p-3 text-left transition hover:border-foreground/35"
                    >
                      <div className="font-mono text-xs text-muted-foreground">
                        {task.displayId}
                      </div>
                      <div className="mt-1 text-sm font-medium break-words">
                        {task.title}
                      </div>
                    </a>
                  ))
                ) : (
                  <div className="rounded-md border border-dashed bg-muted/25 p-3 text-xs text-muted-foreground">
                    No tasks yet.
                  </div>
                )}
              </div>
            </div>
          ))}
        </section>
      </div>

      {selectedTask ? (
        <aside className="fixed inset-y-0 right-0 z-20 w-full max-w-md overflow-y-auto border-l bg-background p-5 shadow-xl">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <p className="font-mono text-xs text-muted-foreground">
                {selectedTask.displayId}
              </p>
              <h2 className="mt-1 text-lg font-semibold tracking-normal break-words">
                {selectedTask.title}
              </h2>
            </div>
            <a
              href={`/projects/${encodeURIComponent(project.key)}`}
              className="rounded-md border px-2 py-1 text-xs text-muted-foreground transition hover:text-foreground"
            >
              Close
            </a>
          </div>
          <section className="mt-5 grid gap-4 text-sm">
            <div>
              <h3 className="text-xs font-semibold text-muted-foreground">
                Body
              </h3>
              <pre className="mt-2 whitespace-pre-wrap rounded-md border bg-muted/25 p-3 font-sans text-sm">
                {selectedTask.bodyMarkdown || "No body yet."}
              </pre>
            </div>
            <div>
              <h3 className="text-xs font-semibold text-muted-foreground">
                Acceptance criteria
              </h3>
              <pre className="mt-2 whitespace-pre-wrap rounded-md border bg-muted/25 p-3 font-sans text-sm">
                {selectedTask.acceptanceCriteriaMarkdown ||
                  "No acceptance criteria yet."}
              </pre>
            </div>
          </section>
        </aside>
      ) : null}
    </main>
  )
}

function ProjectHeader({
  project,
}: {
  project: {
    displayName: string
    key: string
    repoPath: string
  }
}) {
  return (
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
  )
}
