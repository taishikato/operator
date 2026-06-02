import type { KanbanColumn, KanbanTask } from "./kanban-view.ts"
import type { TaskStatus } from "./task-repository.ts"

export type KanbanTaskMove = {
  activeDisplayId: string
  targetStatus: TaskStatus
  targetDisplayId?: string
}

export function moveKanbanTask(
  columns: KanbanColumn[],
  move: KanbanTaskMove
): KanbanColumn[] {
  const activeTask = columns
    .flatMap((column) => column.tasks)
    .find((task) => task.displayId === move.activeDisplayId)

  if (!activeTask) {
    return columns
  }

  return columns.map((column) => {
    const tasksWithoutActive = column.tasks.filter(
      (task) => task.displayId !== move.activeDisplayId
    )
    const nextTasks =
      column.status === move.targetStatus
        ? insertTask(tasksWithoutActive, {
            ...activeTask,
            status: move.targetStatus,
          })
        : tasksWithoutActive

    return {
      ...column,
      tasks: nextTasks.map((task, index) => ({
        ...task,
        position: index + 1,
      })),
    }

    function insertTask(tasks: KanbanTask[], task: KanbanTask) {
      const targetIndex = move.targetDisplayId
        ? tasks.findIndex(
            (candidate) => candidate.displayId === move.targetDisplayId
          )
        : -1

      if (targetIndex === -1) {
        return [...tasks, task]
      }

      return [
        ...tasks.slice(0, targetIndex),
        task,
        ...tasks.slice(targetIndex),
      ]
    }
  })
}

export function applyKanbanBoardFailure({
  lastServerColumns,
  message,
}: {
  lastServerColumns: KanbanColumn[]
  optimisticColumns: KanbanColumn[]
  message: string
}) {
  return {
    columns: lastServerColumns,
    errorMessage: message,
  }
}
