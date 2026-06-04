"use client"

import { Plus, X } from "lucide-react"
import { useRouter } from "next/navigation"
import type { FormEvent } from "react"
import { useEffect, useState } from "react"

import { Button } from "@/components/ui/button"

type CreateTaskSuccessBody = {
  task: {
    displayId: string
  }
}

export function TaskCreateButton({ projectKey }: { projectKey: string }) {
  const router = useRouter()
  const [isOpen, setIsOpen] = useState(false)
  const [title, setTitle] = useState("")
  const [bodyMarkdown, setBodyMarkdown] = useState("")
  const [acceptanceCriteriaMarkdown, setAcceptanceCriteriaMarkdown] =
    useState("")
  const [errorMessage, setErrorMessage] = useState("")
  const [isSaving, setIsSaving] = useState(false)

  // Close the drawer with the Escape key, matching common drawer affordances.
  useEffect(() => {
    if (!isOpen) {
      return
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setIsOpen(false)
      }
    }

    window.addEventListener("keydown", handleKeyDown)
    return () => window.removeEventListener("keydown", handleKeyDown)
  }, [isOpen])

  function resetForm() {
    setTitle("")
    setBodyMarkdown("")
    setAcceptanceCriteriaMarkdown("")
    setErrorMessage("")
  }

  function openDrawer() {
    resetForm()
    setIsOpen(true)
  }

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
        resetForm()
        setIsOpen(false)
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
    <>
      <Button type="button" size="lg" onClick={openDrawer} title="New Task">
        <Plus data-icon="inline-start" />
        New Task
      </Button>

      {isOpen ? (
        <div className="fixed inset-0 z-30">
          <button
            type="button"
            aria-label="Close New Task"
            className="absolute inset-0 bg-foreground/20"
            onClick={() => setIsOpen(false)}
          />

          <aside
            role="dialog"
            aria-label="New Task"
            aria-modal="true"
            className="absolute inset-y-0 right-0 w-full max-w-xl overflow-y-auto border-l bg-background p-5 shadow-xl"
          >
            <div className="flex items-start justify-between gap-4">
              <h2 className="text-lg font-semibold tracking-normal">
                New Task
              </h2>
              <button
                type="button"
                onClick={() => setIsOpen(false)}
                className="inline-flex h-8 w-8 items-center justify-center rounded-md border text-muted-foreground transition hover:text-foreground"
                title="Close"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <form onSubmit={createTask} className="mt-5 grid gap-4 text-sm">
              <label className="grid gap-1.5">
                <span className="text-xs font-medium text-muted-foreground">
                  Title
                </span>
                <input
                  autoFocus
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
                  className="min-h-32 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
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
                  className="min-h-28 resize-y rounded-md border bg-background px-3 py-2 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
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

              <div className="flex items-center justify-end gap-2 border-t pt-4">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setIsOpen(false)}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  disabled={isSaving || title.trim().length === 0}
                  title="Create Task"
                >
                  <Plus data-icon="inline-start" />
                  Create
                </Button>
              </div>
            </form>
          </aside>
        </div>
      ) : null}
    </>
  )
}
