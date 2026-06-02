"use client"

import { Plus } from "lucide-react"
import { useRouter } from "next/navigation"
import type { FormEvent } from "react"
import { useState } from "react"

import { Button } from "@/components/ui/button"

type CreateTaskSuccessBody = {
  task: {
    displayId: string
  }
}

export function TaskCreateForm({ projectKey }: { projectKey: string }) {
  const router = useRouter()
  const [title, setTitle] = useState("")
  const [bodyMarkdown, setBodyMarkdown] = useState("")
  const [acceptanceCriteriaMarkdown, setAcceptanceCriteriaMarkdown] =
    useState("")
  const [errorMessage, setErrorMessage] = useState("")
  const [isSaving, setIsSaving] = useState(false)

  async function createTask(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSaving(true)
    setErrorMessage("")

    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(projectKey)}/tasks`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            title,
            bodyMarkdown,
            acceptanceCriteriaMarkdown,
          }),
        }
      )
      const body = (await response.json()) as
        | CreateTaskSuccessBody
        | { error?: { message?: string } }

      if (response.ok && "task" in body) {
        setTitle("")
        setBodyMarkdown("")
        setAcceptanceCriteriaMarkdown("")
        router.replace(
          `/projects/${encodeURIComponent(projectKey)}?task=${encodeURIComponent(body.task.displayId)}`
        )
        router.refresh()
        return
      }

      const errorBody = body as { error?: { message?: string } }
      setErrorMessage(errorBody.error?.message ?? "Could not create the Task.")
    } catch {
      setErrorMessage("Could not reach the local Task API.")
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <form
      onSubmit={createTask}
      className="grid gap-3 rounded-lg border bg-card p-4 shadow-sm"
    >
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-sm font-semibold">New Task</h2>
        <Button
          type="submit"
          size="sm"
          disabled={isSaving || title.trim().length === 0}
          title="Create Task"
        >
          <Plus data-icon="inline-start" />
          Create
        </Button>
      </div>

      <label className="grid gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">Title</span>
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
          placeholder="Describe the work"
        />
      </label>

      <label className="grid gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">
          Markdown body
        </span>
        <textarea
          value={bodyMarkdown}
          onChange={(event) => setBodyMarkdown(event.target.value)}
          className="min-h-24 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
          placeholder="Context and instructions for the agent"
        />
      </label>

      <label className="grid gap-1.5">
        <span className="text-xs font-medium text-muted-foreground">
          Acceptance criteria
        </span>
        <textarea
          value={acceptanceCriteriaMarkdown}
          onChange={(event) =>
            setAcceptanceCriteriaMarkdown(event.target.value)
          }
          className="min-h-20 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
          placeholder="- What must be true when complete"
        />
      </label>

      {errorMessage ? (
        <div
          role="alert"
          className="rounded-md border border-destructive/35 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        >
          {errorMessage}
        </div>
      ) : null}
    </form>
  )
}
