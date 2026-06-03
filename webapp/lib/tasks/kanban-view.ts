import type { LatestRunSummary } from "../runs/run-repository.ts"
import type { TaskStatus } from "./task-repository.ts"

export type KanbanTask = {
  id: string
  displayId: string
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
  status: TaskStatus
  position: number
  modelOverride: string | null
  reasoningLevelOverride: string | null
  latestRun?: LatestRunSummary | null
}

export type KanbanColumn = {
  status: TaskStatus
  label: string
  tasks: KanbanTask[]
}

const KANBAN_COLUMN_DEFINITIONS: Array<{
  status: TaskStatus
  label: string
}> = [
  { status: "backlog", label: "Backlog" },
  { status: "ready", label: "Ready" },
  { status: "running", label: "Running" },
  { status: "review", label: "Review" },
  { status: "done", label: "Done" },
  { status: "blocked", label: "Blocked" },
]

export function createKanbanColumns(tasks: KanbanTask[]): KanbanColumn[] {
  return KANBAN_COLUMN_DEFINITIONS.map((column) => ({
    ...column,
    tasks: tasks
      .filter((task) => task.status === column.status)
      .sort((first, second) => first.position - second.position),
  }))
}

export function resolveTaskDrawer(
  displayId: string | undefined,
  tasks: KanbanTask[]
) {
  if (!displayId) {
    return null
  }

  return tasks.find((task) => task.displayId === displayId) ?? null
}

export function attachLatestRunSummaries(
  tasks: KanbanTask[],
  latestRunsByTaskId: Record<string, LatestRunSummary>
): KanbanTask[] {
  return tasks.map((task) => ({
    ...task,
    latestRun: latestRunsByTaskId[task.id] ?? null,
  }))
}
