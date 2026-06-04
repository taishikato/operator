import { FolderKanban, Plus, Settings } from "lucide-react"
import Link from "next/link"
import { notFound } from "next/navigation"

import { KanbanBoard } from "@/components/tasks/kanban-board"
import { TaskCreateButton } from "@/components/tasks/task-create-drawer"
import { TaskDrawer } from "@/components/tasks/task-drawer"
import { resolveAppDataPaths } from "@/lib/app-data/app-data"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import { createRunRepository } from "@/lib/runs/run-repository"
import { shouldStartSchedulerFromWebRequest } from "@/lib/cli/operator-runtime-env"
import { ensureProjectSchedulerRuntimeStarted } from "@/lib/scheduler/project-scheduler-runtime"
import {
  attachLatestRunSummaries,
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

  if (shouldStartSchedulerFromWebRequest()) {
    ensureProjectSchedulerRuntimeStarted({ databasePath })
  }

  const tasks = await createTaskRepository({
    databasePath,
  }).listActiveTasksForProject(project.id)
  const kanbanTasksWithoutRuns: KanbanTask[] = tasks.map((task) => ({
    id: task.id,
    displayId: task.displayId,
    title: task.title,
    bodyMarkdown: task.bodyMarkdown,
    acceptanceCriteriaMarkdown: task.acceptanceCriteriaMarkdown,
    status: task.status,
    position: task.position,
    taskBranchName: task.taskBranchName,
    pullRequestUrl: task.pullRequestUrl,
    pullRequestError: task.pullRequestError,
    modelOverride: task.modelOverride,
    reasoningLevelOverride: task.reasoningLevelOverride,
    latestRun: null,
  }))
  const latestRunsByTaskId = await createRunRepository({
    databasePath,
    appDataPaths: resolveAppDataPaths({}),
  }).listLatestRunSummariesForTasks(
    kanbanTasksWithoutRuns.map((task) => task.id)
  )
  const kanbanTasks = attachLatestRunSummaries(
    kanbanTasksWithoutRuns,
    latestRunsByTaskId
  )
  const columns = createKanbanColumns(kanbanTasks)
  const selectedTask = resolveTaskDrawer(selectedTaskDisplayId, kanbanTasks)

  return (
    <main className="min-h-svh bg-background">
      <ProjectHeader project={project} />

      <div className="px-4 py-5 sm:px-6 lg:px-8">
        <KanbanBoard
          projectKey={project.key}
          scheduledRunLimit={project.schedule.scheduledRunLimit}
          initialColumns={columns}
        />
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
    schedule: {
      enabled: boolean
    }
  }
}) {
  return (
    <header className="border-b px-4 py-4 sm:px-6 lg:px-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <Link
            href="/"
            className="mb-1 inline-flex items-center gap-1.5 text-xs font-medium text-muted-foreground transition hover:text-foreground"
          >
            <FolderKanban className="h-3.5 w-3.5" />
            Projects
          </Link>
          <p className="text-xs font-medium text-muted-foreground uppercase">
            Project {project.key}
          </p>
          <h1 className="truncate text-xl font-semibold tracking-normal">
            {project.displayName}
          </h1>
          <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
            {project.repoPath}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="rounded-md border bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
            Schedule {project.schedule.enabled ? "on" : "off"}
          </div>
          <Link
            href="/projects/new"
            className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
          >
            <Plus className="h-4 w-4" />
            Add Project
          </Link>
          <a
            href={`/projects/${encodeURIComponent(project.key)}/settings`}
            className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
          >
            <Settings className="h-4 w-4" />
            Settings
          </a>
          <TaskCreateButton projectKey={project.key} />
        </div>
      </div>
    </header>
  )
}
