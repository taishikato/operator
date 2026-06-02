import { notFound } from "next/navigation"

import { KanbanBoard } from "@/components/tasks/kanban-board"
import { TaskCreateForm } from "@/components/tasks/task-create-form"
import { TaskDrawer } from "@/components/tasks/task-drawer"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import {
  createKanbanColumns,
  resolveTaskDrawer,
  type KanbanTask,
} from "@/lib/tasks/kanban-view"
import { taskDrawerRemountKey } from "@/lib/tasks/task-drawer-mount"
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
    modelOverride: task.modelOverride,
    reasoningLevelOverride: task.reasoningLevelOverride,
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

        <KanbanBoard projectKey={project.key} initialColumns={columns} />
      </div>

      {selectedTask ? (
        <TaskDrawer
          key={taskDrawerRemountKey(selectedTask.displayId)}
          projectKey={project.key}
          task={selectedTask}
        />
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
