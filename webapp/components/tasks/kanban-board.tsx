"use client"

import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core"
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable"
import { CSS } from "@dnd-kit/utilities"
import { GripVertical, Play } from "lucide-react"
import { useRouter } from "next/navigation"
import { useEffect, useRef, useState } from "react"

import {
  applyKanbanBoardFailure,
  moveKanbanTask,
} from "@/lib/tasks/kanban-board-state"
import {
  createKanbanColumns,
  type KanbanColumn,
  type KanbanTask,
} from "@/lib/tasks/kanban-view"
import type { TaskStatus } from "@/lib/tasks/task-repository"

type BoardResponseBody =
  | {
      tasks: KanbanTask[]
    }
  | {
      error?: {
        message?: string
      }
    }

const TASK_ID_PREFIX = "task:"
const COLUMN_ID_PREFIX = "column:"
const MAX_READY_BATCH_COUNT = 100

export function KanbanBoard({
  projectKey,
  scheduledRunLimit = 1,
  initialColumns,
}: {
  projectKey: string
  scheduledRunLimit?: number
  initialColumns: KanbanColumn[]
}) {
  const router = useRouter()
  const [columns, setColumns] = useState(initialColumns)
  const [lastServerColumns, setLastServerColumns] = useState(initialColumns)
  const [errorMessage, setErrorMessage] = useState("")
  const [isSaving, setIsSaving] = useState(false)
  const [isRunningReadyBatch, setIsRunningReadyBatch] = useState(false)
  const [runningTaskIds, setRunningTaskIds] = useState<Set<string>>(new Set())
  const lastSyncedInitialColumns = useRef(initialColumns)
  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    })
  )

  useEffect(() => {
    if (initialColumns === lastSyncedInitialColumns.current || isSaving) {
      return
    }

    lastSyncedInitialColumns.current = initialColumns
    setColumns(initialColumns)
    setLastServerColumns(initialColumns)
    setErrorMessage("")
  }, [initialColumns, isSaving])

  async function saveBoard(nextColumns: KanbanColumn[]) {
    setIsSaving(true)
    setErrorMessage("")

    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(projectKey)}/tasks/board`,
        {
          method: "PATCH",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            columns: nextColumns
              .filter((column) => column.status !== "running")
              .map((column) => ({
                status: column.status,
                taskDisplayIds: column.tasks.map((task) => task.displayId),
              })),
          }),
        }
      )
      const body = (await response.json()) as BoardResponseBody

      if (response.ok && "tasks" in body) {
        const serverColumns = createKanbanColumns(body.tasks)
        setColumns(serverColumns)
        setLastServerColumns(serverColumns)
        router.refresh()
        return
      }

      recoverFromFailedSave(nextColumns, getBoardErrorMessage(body))
    } catch {
      recoverFromFailedSave(
        nextColumns,
        "Could not reach the local Task board API."
      )
    } finally {
      setIsSaving(false)
    }
  }

  function recoverFromFailedSave(
    optimisticColumns: KanbanColumn[],
    message: string
  ) {
    const recovered = applyKanbanBoardFailure({
      lastServerColumns,
      optimisticColumns,
      message,
    })
    setColumns(recovered.columns)
    setErrorMessage(recovered.errorMessage)
  }

  function handleDragEnd(event: DragEndEvent) {
    const activeDisplayId = parseTaskId(String(event.active.id))
    const overId = event.over ? String(event.over.id) : null

    if (!activeDisplayId || !overId) {
      return
    }

    const activeTask = findTask(columns, activeDisplayId)

    if (!activeTask || activeTask.status === "running") {
      return
    }

    const target = resolveDropTarget(columns, overId)

    if (!target || target.status === "running") {
      setErrorMessage("Running Tasks are controlled by the system.")
      return
    }

    if (
      activeTask.status === target.status &&
      activeDisplayId === target.displayId
    ) {
      return
    }

    const nextColumns = moveKanbanTask(columns, {
      activeDisplayId,
      targetStatus: target.status,
      targetDisplayId: target.displayId,
    })

    setColumns(nextColumns)
    void saveBoard(nextColumns)
  }

  async function runTaskNow(task: KanbanTask) {
    setRunningTaskIds((current) => new Set(current).add(task.displayId))
    setErrorMessage("")

    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(projectKey)}/tasks/${encodeURIComponent(task.displayId)}/run`,
        { method: "POST" }
      )
      const body = (await response.json()) as BoardResponseBody

      if (!response.ok) {
        setErrorMessage(getBoardErrorMessage(body))
        return
      }

      router.refresh()
    } catch {
      setErrorMessage("Could not reach the local Run Now API.")
    } finally {
      setRunningTaskIds((current) => {
        const next = new Set(current)
        next.delete(task.displayId)
        return next
      })
    }
  }

  async function runReadyTasks() {
    const requestedCount = window.prompt(
      "Ready Tasks to run",
      String(scheduledRunLimit)
    )

    if (requestedCount === null) {
      return
    }

    const count = Number(requestedCount)

    if (!Number.isInteger(count) || count < 1) {
      setErrorMessage("Enter a whole number of Ready Tasks to run.")
      return
    }

    if (count > MAX_READY_BATCH_COUNT) {
      setErrorMessage("Enter 100 or fewer Ready Tasks to run.")
      return
    }

    setIsRunningReadyBatch(true)
    setErrorMessage("")

    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(projectKey)}/tasks/run-ready`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ count }),
        }
      )
      const body = (await response.json()) as BoardResponseBody

      if (!response.ok) {
        setErrorMessage(getBoardErrorMessage(body))
        return
      }

      router.refresh()
    } catch {
      setErrorMessage("Could not reach the local Ready batch API.")
    } finally {
      setIsRunningReadyBatch(false)
    }
  }

  return (
    <div className="grid min-w-0 gap-3">
      {errorMessage ? (
        <div
          role="alert"
          className="rounded-md border border-destructive/35 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        >
          {errorMessage}
        </div>
      ) : null}

      <DndContext sensors={sensors} onDragEnd={handleDragEnd}>
        <section
          aria-busy={isSaving}
          className="grid min-w-0 gap-3 md:grid-cols-2 xl:grid-cols-6"
        >
          {columns.map((column) => (
            <KanbanBoardColumn
              key={column.status}
              column={column}
              projectKey={projectKey}
              runningTaskIds={runningTaskIds}
              isRunningReadyBatch={isRunningReadyBatch}
              onRunReadyTasks={runReadyTasks}
              onRunTask={runTaskNow}
            />
          ))}
        </section>
      </DndContext>
    </div>
  )
}

function KanbanBoardColumn({
  column,
  projectKey,
  runningTaskIds,
  isRunningReadyBatch,
  onRunReadyTasks,
  onRunTask,
}: {
  column: KanbanColumn
  projectKey: string
  runningTaskIds: Set<string>
  isRunningReadyBatch: boolean
  onRunReadyTasks: () => void
  onRunTask: (task: KanbanTask) => void
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: columnId(column.status),
    disabled: column.status === "running",
  })

  return (
    <div
      ref={setNodeRef}
      className={[
        "min-h-56 rounded-lg border bg-card p-3 shadow-sm",
        isOver ? "border-foreground/35" : "",
      ].join(" ")}
    >
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold">{column.label}</h2>
        <div className="flex items-center gap-1">
          {column.status === "ready" ? (
            <button
              type="button"
              aria-label="Run Ready Tasks"
              title="Run Ready Tasks"
              disabled={isRunningReadyBatch || column.tasks.length === 0}
              className="inline-flex h-6 w-6 items-center justify-center rounded-md text-muted-foreground transition hover:bg-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40"
              onClick={onRunReadyTasks}
            >
              <Play className="h-3.5 w-3.5" />
            </button>
          ) : null}
          <span className="rounded-full border px-2 py-0.5 text-xs text-muted-foreground">
            {column.tasks.length}
          </span>
        </div>
      </div>
      <SortableContext
        items={column.tasks.map((task) => taskId(task.displayId))}
        strategy={verticalListSortingStrategy}
      >
        <div className="mt-4 grid gap-2">
          {column.tasks.length > 0 ? (
            column.tasks.map((task) => (
              <KanbanTaskCard
                key={task.id}
                projectKey={projectKey}
                task={task}
                isRunPending={runningTaskIds.has(task.displayId)}
                onRunTask={onRunTask}
              />
            ))
          ) : (
            <div className="rounded-md border border-dashed bg-muted/25 p-3 text-xs text-muted-foreground">
              No tasks yet.
            </div>
          )}
        </div>
      </SortableContext>
    </div>
  )
}

function KanbanTaskCard({
  projectKey,
  task,
  isRunPending,
  onRunTask,
}: {
  projectKey: string
  task: KanbanTask
  isRunPending: boolean
  onRunTask: (task: KanbanTask) => void
}) {
  const disabled = task.status === "running"
  const canRun = canRunTaskNow(task.status)
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({
    id: taskId(task.displayId),
    disabled,
  })
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={[
        "group rounded-md border bg-background p-3 text-left transition hover:border-foreground/35",
        isDragging ? "opacity-60" : "",
      ].join(" ")}
    >
      <div className="flex items-start justify-between gap-2">
        <a
          href={`/projects/${encodeURIComponent(projectKey)}?task=${encodeURIComponent(task.displayId)}`}
          className="min-w-0 grow"
        >
          <div className="font-mono text-xs text-muted-foreground">
            {task.displayId}
          </div>
          <div className="mt-1 text-sm font-medium break-words">
            {task.title}
          </div>
        </a>
        <div className="flex shrink-0 items-center gap-1">
          {canRun ? (
            <button
              type="button"
              aria-label={`Run ${task.displayId}`}
              title="Run Now"
              disabled={isRunPending}
              className="inline-flex h-6 w-6 items-center justify-center rounded-md text-muted-foreground transition hover:bg-muted hover:text-foreground disabled:cursor-wait disabled:opacity-40"
              onClick={(event) => {
                event.preventDefault()
                event.stopPropagation()
                onRunTask(task)
              }}
            >
              <Play className="h-3.5 w-3.5" />
            </button>
          ) : null}
          <button
            type="button"
            aria-label={`Drag ${task.displayId}`}
            title={
              disabled
                ? "Running Tasks are controlled by the system"
                : "Drag Task"
            }
            disabled={disabled}
            className="inline-flex h-6 w-6 items-center justify-center rounded-md text-muted-foreground transition hover:bg-muted hover:text-foreground disabled:cursor-not-allowed disabled:opacity-40"
            {...attributes}
            {...listeners}
          >
            <GripVertical className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  )
}

function canRunTaskNow(status: TaskStatus) {
  return (
    status === "backlog" ||
    status === "ready" ||
    status === "blocked" ||
    status === "review"
  )
}

function resolveDropTarget(columns: KanbanColumn[], overId: string) {
  const columnStatus = parseColumnId(overId)

  if (columnStatus) {
    return { status: columnStatus }
  }

  const taskDisplayId = parseTaskId(overId)

  if (!taskDisplayId) {
    return null
  }

  const column = columns.find((candidate) =>
    candidate.tasks.some((task) => task.displayId === taskDisplayId)
  )

  return column
    ? {
        status: column.status,
        displayId: taskDisplayId,
      }
    : null
}

function findTask(columns: KanbanColumn[], displayId: string) {
  return columns
    .flatMap((column) => column.tasks)
    .find((task) => task.displayId === displayId)
}

function getBoardErrorMessage(body: BoardResponseBody) {
  if ("error" in body && body.error?.message) {
    return body.error.message
  }

  return "Could not save board order."
}

function taskId(displayId: string) {
  return `${TASK_ID_PREFIX}${displayId}`
}

function columnId(status: TaskStatus) {
  return `${COLUMN_ID_PREFIX}${status}`
}

function parseTaskId(id: string) {
  return id.startsWith(TASK_ID_PREFIX) ? id.slice(TASK_ID_PREFIX.length) : null
}

function parseColumnId(id: string): TaskStatus | null {
  if (!id.startsWith(COLUMN_ID_PREFIX)) {
    return null
  }

  return id.slice(COLUMN_ID_PREFIX.length) as TaskStatus
}
