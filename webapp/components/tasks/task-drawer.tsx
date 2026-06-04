"use client"

import {
  CheckCircle2,
  Eye,
  FileText,
  GitPullRequest,
  Pencil,
  RotateCcw,
  Save,
  X,
} from "lucide-react"
import { useRouter } from "next/navigation"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  createTaskEditState,
  discardTaskEditDraft,
  getTaskEditSavePayload,
  hasUnsavedTaskEditChanges,
  updateTaskEditDraft,
  type TaskEditState,
  type TaskInstructionFields,
} from "@/lib/tasks/task-editing-state"
import { getTaskDrawerActionState } from "@/lib/tasks/task-drawer-actions"
import type { TaskStatus } from "@/lib/tasks/task-repository"

type TaskDrawerTask = TaskInstructionFields & {
  displayId: string
  title: string
  status: TaskStatus
  taskBranchName: string | null
  pullRequestUrl: string | null
  pullRequestError: string | null
  latestRun?: {
    id: string
    status: string
    blockedReason: string | null
    startedAt: string
    finishedAt: string | null
    updatedAt: string
    rawLogPath: string
  } | null
}

type TaskResponseBody =
  | {
      task: TaskInstructionFields & {
        status: TaskStatus
        pullRequestUrl?: string | null
        pullRequestError?: string | null
      }
    }
  | {
      error?: {
        message?: string
      }
    }

type TaskPullRequestDraft = {
  remote: string
  remoteUrl: string
  branchName: string
  baseBranch: string
  commitSha: string
  title: string
  body: string
  draft: true
}

type TaskPullRequestDraftResponseBody =
  | {
      draft: TaskPullRequestDraft
    }
  | {
      error?: {
        message?: string
      }
    }

export function TaskDrawer({
  projectKey,
  task,
}: {
  projectKey: string
  task: TaskDrawerTask
}) {
  const router = useRouter()
  const [editState, setEditState] = useState<TaskEditState>(() =>
    createTaskEditState(toInstructionFields(task))
  )
  const [bodyPreview, setBodyPreview] = useState(false)
  const [criteriaPreview, setCriteriaPreview] = useState(false)
  const [errorMessage, setErrorMessage] = useState("")
  const [isSaving, setIsSaving] = useState(false)
  const [isMovingReady, setIsMovingReady] = useState(false)
  const [isCreatingPullRequest, setIsCreatingPullRequest] = useState(false)
  const [pullRequestDraft, setPullRequestDraft] =
    useState<TaskPullRequestDraft | null>(null)
  const [pullRequestTitle, setPullRequestTitle] = useState("")
  const [pullRequestBody, setPullRequestBody] = useState("")
  const hasChanges = hasUnsavedTaskEditChanges(editState)
  const actionState = getTaskDrawerActionState({
    hasChanges,
    isSaving,
    isMovingReady,
    isCreatingPullRequest,
    taskStatus: task.status,
    taskBranchName: task.taskBranchName,
    pullRequestUrl: task.pullRequestUrl,
    pullRequestTitle: pullRequestDraft ? pullRequestTitle : null,
  })
  const pullRequestCreateDisabled = actionState.createPullRequestDisabled

  function updateDraft(patch: Partial<TaskInstructionFields>) {
    setEditState((current) => updateTaskEditDraft(current, patch))
  }

  async function saveTask() {
    setIsSaving(true)
    setErrorMessage("")

    try {
      await patchTaskAndRefresh(
        getTaskEditSavePayload(editState),
        "Could not save the Task."
      )
    } catch {
      setErrorMessage("Could not reach the local Task API.")
    } finally {
      setIsSaving(false)
    }
  }

  async function moveToReady() {
    setIsMovingReady(true)
    setErrorMessage("")

    try {
      await patchTaskAndRefresh({ status: "ready" }, "Could not move the Task.")
    } catch {
      setErrorMessage("Could not reach the local Task API.")
    } finally {
      setIsMovingReady(false)
    }
  }

  async function preparePullRequest() {
    setIsCreatingPullRequest(true)
    setErrorMessage("")

    try {
      const response = await fetch(pullRequestApiPath(), { method: "GET" })
      const body = (await response.json()) as TaskPullRequestDraftResponseBody

      if (response.ok && "draft" in body) {
        setPullRequestDraft(body.draft)
        setPullRequestTitle(body.draft.title)
        setPullRequestBody(body.draft.body)
        return
      }

      setErrorMessage(
        getErrorMessage(body, "Could not prepare the pull request.")
      )
    } catch {
      setErrorMessage("Could not reach the local pull request API.")
    } finally {
      setIsCreatingPullRequest(false)
    }
  }

  async function createPullRequest() {
    if (!pullRequestDraft) {
      return
    }

    setIsCreatingPullRequest(true)
    setErrorMessage("")

    try {
      const response = await fetch(pullRequestApiPath(), {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          title: pullRequestTitle,
          body: pullRequestBody,
          draft: true,
        }),
      })
      const body = (await response.json()) as TaskResponseBody

      if (response.ok && "task" in body) {
        setPullRequestDraft(null)
        router.refresh()
        return
      }

      setErrorMessage(
        getErrorMessage(body, "Could not create the pull request.")
      )
    } catch {
      setErrorMessage("Could not reach the local pull request API.")
    } finally {
      setIsCreatingPullRequest(false)
    }
  }

  async function patchTaskAndRefresh(
    payload: Record<string, unknown>,
    fallbackErrorMessage: string
  ) {
    const response = await patchTask(payload)
    const body = (await response.json()) as TaskResponseBody

    if (response.ok && "task" in body) {
      setEditState(createTaskEditState(toInstructionFields(body.task)))
      router.refresh()
      return
    }

    setErrorMessage(getErrorMessage(body, fallbackErrorMessage))
  }

  function patchTask(payload: Record<string, unknown>) {
    return fetch(
      `/api/projects/${encodeURIComponent(projectKey)}/tasks/${encodeURIComponent(task.displayId)}`,
      {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      }
    )
  }

  function pullRequestApiPath() {
    return `/api/projects/${encodeURIComponent(projectKey)}/tasks/${encodeURIComponent(task.displayId)}/pull-request`
  }

  return (
    <aside className="fixed inset-y-0 right-0 z-20 w-full max-w-xl overflow-y-auto border-l bg-background p-5 shadow-xl">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="font-mono text-xs text-muted-foreground">
            {task.displayId}
          </p>
          <h2 className="mt-1 text-lg font-semibold tracking-normal break-words">
            {editState.saved.title || "Untitled Task"}
          </h2>
          <p className="mt-1 text-xs text-muted-foreground capitalize">
            {task.status}
          </p>
        </div>
        <a
          href={`/projects/${encodeURIComponent(projectKey)}`}
          className="inline-flex h-8 w-8 items-center justify-center rounded-md border text-muted-foreground transition hover:text-foreground"
          title="Close"
        >
          <X className="h-4 w-4" />
        </a>
      </div>

      {task.latestRun ? <LatestRunSummary run={task.latestRun} /> : null}

      {task.pullRequestUrl ? (
        <section className="mt-5 rounded-md border bg-muted/20 p-3 text-sm">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs font-medium text-muted-foreground">
                Pull request
              </p>
              <a
                href={task.pullRequestUrl}
                className="mt-1 block truncate font-mono text-xs underline underline-offset-2"
              >
                {task.pullRequestUrl}
              </a>
            </div>
            <GitPullRequest className="h-4 w-4 shrink-0 text-muted-foreground" />
          </div>
        </section>
      ) : null}

      {task.pullRequestError ? (
        <div
          role="alert"
          className="mt-5 rounded-md border border-destructive/35 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        >
          {task.pullRequestError}
        </div>
      ) : null}

      <section className="mt-5 grid gap-4 text-sm">
        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Title
          </span>
          <input
            value={editState.draft.title}
            onChange={(event) => updateDraft({ title: event.target.value })}
            disabled={actionState.inputsDisabled}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>

        <MarkdownEditor
          label="Body"
          value={editState.draft.bodyMarkdown}
          preview={bodyPreview}
          onPreviewChange={setBodyPreview}
          onChange={(bodyMarkdown) => updateDraft({ bodyMarkdown })}
          disabled={actionState.inputsDisabled}
        />

        <MarkdownEditor
          label="Acceptance criteria"
          value={editState.draft.acceptanceCriteriaMarkdown}
          preview={criteriaPreview}
          onPreviewChange={setCriteriaPreview}
          onChange={(acceptanceCriteriaMarkdown) =>
            updateDraft({ acceptanceCriteriaMarkdown })
          }
          disabled={actionState.inputsDisabled}
        />

        <div className="grid gap-3 sm:grid-cols-2">
          <label className="grid gap-1.5">
            <span className="text-xs font-medium text-muted-foreground">
              Model override
            </span>
            <select
              value={editState.draft.modelOverride ?? ""}
              onChange={(event) =>
                updateDraft({
                  modelOverride: event.target.value || null,
                })
              }
              disabled={actionState.inputsDisabled}
              className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <option value="">Project default</option>
              <option value="cursor/gpt-5">cursor/gpt-5</option>
              <option value="cursor/gpt-5.1">cursor/gpt-5.1</option>
            </select>
          </label>

          <label className="grid gap-1.5">
            <span className="text-xs font-medium text-muted-foreground">
              Reasoning override
            </span>
            <select
              value={editState.draft.reasoningLevelOverride ?? ""}
              onChange={(event) =>
                updateDraft({
                  reasoningLevelOverride: event.target.value || null,
                })
              }
              disabled={actionState.inputsDisabled}
              className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
            >
              <option value="">Project default</option>
              <option value="low">low</option>
              <option value="medium">medium</option>
              <option value="high">high</option>
            </select>
          </label>
        </div>

        {errorMessage ? (
          <div
            role="alert"
            className="rounded-md border border-destructive/35 bg-destructive/10 px-3 py-2 text-sm text-destructive"
          >
            {errorMessage}
          </div>
        ) : null}

        {pullRequestDraft ? (
          <PullRequestConfirmation
            draft={pullRequestDraft}
            title={pullRequestTitle}
            body={pullRequestBody}
            disabled={isCreatingPullRequest}
            createDisabled={pullRequestCreateDisabled}
            onTitleChange={setPullRequestTitle}
            onBodyChange={setPullRequestBody}
            onCancel={() => setPullRequestDraft(null)}
            onCreate={createPullRequest}
          />
        ) : null}

        <div className="flex flex-wrap items-center justify-between gap-2 border-t pt-4">
          <Button
            type="button"
            variant="outline"
            onClick={moveToReady}
            disabled={actionState.readyDisabled}
            title={actionState.readyTitle}
          >
            <CheckCircle2 data-icon="inline-start" />
            Ready
          </Button>

          <div className="flex flex-wrap items-center gap-2">
            {actionState.createPullRequestVisible ? (
              <Button
                type="button"
                variant="outline"
                onClick={preparePullRequest}
                disabled={actionState.createPullRequestDisabled}
                title={actionState.createPullRequestTitle}
              >
                <GitPullRequest data-icon="inline-start" />
                Create PR
              </Button>
            ) : null}
            <Button
              type="button"
              variant="outline"
              onClick={() =>
                setEditState((current) => discardTaskEditDraft(current))
              }
              disabled={actionState.discardDisabled}
              title="Discard changes"
            >
              <RotateCcw data-icon="inline-start" />
              Discard
            </Button>
            <Button
              type="button"
              onClick={saveTask}
              disabled={actionState.saveDisabled}
              title="Save changes"
            >
              <Save data-icon="inline-start" />
              Save
            </Button>
          </div>
        </div>
      </section>
    </aside>
  )
}

function PullRequestConfirmation({
  draft,
  title,
  body,
  disabled,
  createDisabled,
  onTitleChange,
  onBodyChange,
  onCancel,
  onCreate,
}: {
  draft: TaskPullRequestDraft
  title: string
  body: string
  disabled: boolean
  createDisabled: boolean
  onTitleChange: (title: string) => void
  onBodyChange: (body: string) => void
  onCancel: () => void
  onCreate: () => void
}) {
  return (
    <section className="rounded-md border bg-muted/20 p-3">
      <div className="flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold">Pull request</h3>
        <span className="rounded-md border bg-background px-2 py-0.5 text-xs font-medium">
          Draft
        </span>
      </div>
      <dl className="mt-3 grid gap-2 text-xs">
        <ConfirmationRow label="Remote" value={draft.remote} />
        <ConfirmationRow label="Remote URL" value={draft.remoteUrl} />
        <ConfirmationRow label="Branch" value={draft.branchName} />
        <ConfirmationRow label="Base" value={draft.baseBranch} />
        <ConfirmationRow label="Commit" value={draft.commitSha} />
      </dl>
      <label className="mt-3 grid gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">
          PR title
        </span>
        <input
          value={title}
          onChange={(event) => onTitleChange(event.target.value)}
          disabled={disabled}
          className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
        />
      </label>
      <label className="mt-3 grid gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">
          PR body
        </span>
        <textarea
          value={body}
          onChange={(event) => onBodyChange(event.target.value)}
          disabled={disabled}
          className="min-h-28 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
        />
      </label>
      <div className="mt-3 flex justify-end gap-2">
        <Button
          type="button"
          variant="outline"
          onClick={onCancel}
          disabled={disabled}
        >
          Cancel
        </Button>
        <Button
          type="button"
          onClick={onCreate}
          disabled={createDisabled}
          title={
            title.trim().length === 0 ? "Enter a pull request title" : undefined
          }
        >
          <GitPullRequest data-icon="inline-start" />
          Create draft PR
        </Button>
      </div>
    </section>
  )
}

function ConfirmationRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid grid-cols-[90px_minmax(0,1fr)] gap-2">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="min-w-0 font-mono break-words">{value}</dd>
    </div>
  )
}

function LatestRunSummary({
  run,
}: {
  run: NonNullable<TaskDrawerTask["latestRun"]>
}) {
  return (
    <section className="mt-5 rounded-md border bg-muted/20 p-3 text-sm">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-medium text-muted-foreground">
            Latest run
          </p>
          <p className="mt-1 font-mono text-xs text-muted-foreground">
            {run.id}
          </p>
        </div>
        <a
          href={run.rawLogPath}
          className="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-md border bg-background px-2.5 text-xs font-medium transition hover:bg-accent"
        >
          <FileText className="h-3.5 w-3.5" />
          Raw log
        </a>
      </div>
      <dl className="mt-3 grid grid-cols-2 gap-3">
        <div>
          <dt className="text-xs text-muted-foreground">Status</dt>
          <dd className="mt-0.5 text-sm font-medium">{run.status}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Reason</dt>
          <dd className="mt-0.5 truncate text-sm">
            {run.blockedReason ?? "-"}
          </dd>
        </div>
      </dl>
    </section>
  )
}

function MarkdownEditor({
  label,
  value,
  preview,
  onPreviewChange,
  onChange,
  disabled = false,
}: {
  label: string
  value: string
  preview: boolean
  onPreviewChange: (preview: boolean) => void
  onChange: (value: string) => void
  disabled?: boolean
}) {
  return (
    <div className="grid gap-1.5">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-medium text-muted-foreground">
          {label}
        </span>
        <div className="inline-flex rounded-md border bg-muted/25 p-0.5">
          <button
            type="button"
            onClick={() => onPreviewChange(false)}
            disabled={disabled}
            className={`inline-flex h-7 items-center gap-1 rounded px-2 text-xs transition disabled:cursor-not-allowed disabled:opacity-50 ${
              preview ? "text-muted-foreground" : "bg-background shadow-sm"
            }`}
            title="Edit markdown"
          >
            <Pencil className="h-3.5 w-3.5" />
            Edit
          </button>
          <button
            type="button"
            onClick={() => onPreviewChange(true)}
            disabled={disabled}
            className={`inline-flex h-7 items-center gap-1 rounded px-2 text-xs transition disabled:cursor-not-allowed disabled:opacity-50 ${
              preview ? "bg-background shadow-sm" : "text-muted-foreground"
            }`}
            title="Preview markdown"
          >
            <Eye className="h-3.5 w-3.5" />
            Preview
          </button>
        </div>
      </div>

      {preview ? (
        <MarkdownPreview markdown={value} />
      ) : (
        <textarea
          value={value}
          onChange={(event) => onChange(event.target.value)}
          disabled={disabled}
          className="min-h-32 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
        />
      )}
    </div>
  )
}

function MarkdownPreview({ markdown }: { markdown: string }) {
  const lines =
    markdown.trim().length > 0 ? markdown.split("\n") : ["No content."]

  return (
    <div className="min-h-32 rounded-md border bg-muted/25 px-3 py-2 text-sm">
      {lines.map((line, index) => {
        const trimmed = line.trim()

        if (trimmed.startsWith("### ")) {
          return (
            <h4 key={index} className="mt-2 font-semibold first:mt-0">
              {trimmed.slice(4)}
            </h4>
          )
        }

        if (trimmed.startsWith("## ")) {
          return (
            <h3 key={index} className="mt-2 font-semibold first:mt-0">
              {trimmed.slice(3)}
            </h3>
          )
        }

        if (trimmed.startsWith("# ")) {
          return (
            <h2 key={index} className="mt-2 font-semibold first:mt-0">
              {trimmed.slice(2)}
            </h2>
          )
        }

        if (trimmed.startsWith("- ")) {
          return (
            <div key={index} className="flex gap-2">
              <span aria-hidden="true">-</span>
              <span className="min-w-0 break-words">{trimmed.slice(2)}</span>
            </div>
          )
        }

        return (
          <p key={index} className="min-h-5 break-words">
            {line}
          </p>
        )
      })}
    </div>
  )
}

function toInstructionFields(
  task: TaskInstructionFields
): TaskInstructionFields {
  return {
    title: task.title,
    bodyMarkdown: task.bodyMarkdown,
    acceptanceCriteriaMarkdown: task.acceptanceCriteriaMarkdown,
    modelOverride: task.modelOverride,
    reasoningLevelOverride: task.reasoningLevelOverride,
  }
}

function getErrorMessage(body: unknown, fallback: string) {
  if (
    body &&
    typeof body === "object" &&
    "error" in body &&
    body.error &&
    typeof body.error === "object" &&
    "message" in body.error &&
    typeof body.error.message === "string"
  ) {
    return body.error.message
  }

  return fallback
}
