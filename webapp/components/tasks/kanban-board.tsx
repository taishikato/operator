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
import { GitPullRequest, GripVertical, Play } from "lucide-react"
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
    <div className="flex min-w-0 flex-col gap-3">
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
          className="-mx-4 flex items-start gap-4 overflow-x-auto px-4 pb-4 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8 [scrollbar-width:thin]"
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
    <div className="flex w-80 shrink-0 flex-col">
      <div className="flex items-center justify-between gap-2 px-1 pb-3">
        <div className="flex min-w-0 items-center gap-2">
          <ColumnStatusDot status={column.status} />
          <h2 className="truncate text-[13px] font-semibold text-foreground">
            {column.label}
          </h2>
          <span className="text-xs text-muted-foreground tabular-nums">
            {column.tasks.length}
          </span>
        </div>
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
      </div>
      <SortableContext
        items={column.tasks.map((task) => taskId(task.displayId))}
        strategy={verticalListSortingStrategy}
      >
        <div
          ref={setNodeRef}
          className={[
            "flex min-h-72 flex-col gap-2 rounded-xl p-1 transition-colors",
            isOver ? "bg-muted/40" : "",
          ].join(" ")}
        >
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
            <div className="flex min-h-24 items-center justify-center rounded-lg border border-dashed border-border/70 text-xs text-muted-foreground/70">
              No tasks yet
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
        "group rounded-lg border border-border bg-card px-3 py-2.5 text-left shadow-sm transition-colors hover:border-foreground/20",
        isDragging ? "opacity-60 shadow-md" : "",
      ].join(" ")}
    >
      <div className="flex items-start justify-between gap-1.5">
        <a
          href={`/projects/${encodeURIComponent(projectKey)}?task=${encodeURIComponent(task.displayId)}`}
          className="min-w-0 grow"
        >
          <div className="font-mono text-[11px] tracking-tight text-muted-foreground">
            {task.displayId}
          </div>
          <div className="mt-1 text-[13px] leading-snug font-medium break-words text-foreground">
            {task.title}
          </div>
        </a>
        <div className="flex shrink-0 items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
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
            className="inline-flex h-6 w-6 cursor-grab items-center justify-center rounded-md text-muted-foreground transition hover:bg-muted hover:text-foreground active:cursor-grabbing disabled:cursor-not-allowed disabled:opacity-40"
            {...attributes}
            {...listeners}
          >
            <GripVertical className="h-4 w-4" />
          </button>
        </div>
      </div>
      {task.pullRequestUrl ? (
        <div className="mt-2.5 flex">
          <a
            href={task.pullRequestUrl}
            className="inline-flex h-6 items-center gap-1 rounded-md border border-border bg-muted/25 px-2 text-[11px] font-medium text-muted-foreground transition hover:bg-muted hover:text-foreground"
            onClick={(event) => event.stopPropagation()}
          >
            <GitPullRequest className="h-3.5 w-3.5" />
            PR
          </a>
        </div>
      ) : null}
    </div>
  )
}

const COLUMN_STATUS_DOT: Record<TaskStatus, string> = {
  // Status indicators are the one place color earns its keep on this board.
  backlog: "border border-dashed border-muted-foreground/70 bg-transparent",
  ready: "bg-blue-500",
  running: "bg-amber-500",
  review: "bg-violet-500",
  done: "bg-emerald-500",
  blocked: "bg-rose-500",
}

function ColumnStatusDot({ status }: { status: TaskStatus }) {
  return (
    <span
      aria-hidden
      className={[
        "h-2.5 w-2.5 shrink-0 rounded-full",
        COLUMN_STATUS_DOT[status],
      ].join(" ")}
    />
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
