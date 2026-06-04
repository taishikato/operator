"use client"

import { FolderOpen, Save } from "lucide-react"
import { useRouter } from "next/navigation"
import type { FormEvent } from "react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  applyCreateProjectError,
  applyDetectProjectError,
  applyProjectKeyChange,
  applyRepositoryPathChange,
  canSubmitAddProjectForm,
  createInitialAddProjectFormState,
  type AddProjectApiErrorBody,
} from "@/lib/projects/add-project-ui-state"

type CreateProjectSuccessBody = {
  route: {
    projectPath: string
  }
}

export function AddProjectForm() {
  const router = useRouter()
  const [state, setState] = useState(createInitialAddProjectFormState)
  const [isSaving, setIsSaving] = useState(false)
  const [isBrowsing, setIsBrowsing] = useState(false)

  async function browseProjectPath() {
    setIsBrowsing(true)

    try {
      const response = await fetch("/api/projects/browse", { method: "POST" })
      const body = (await response.json()) as
        | { path: string }
        | AddProjectApiErrorBody

      if (response.ok && "path" in body) {
        setState((current) => applyRepositoryPathChange(current, body.path))
        return
      }

      setState((current) =>
        applyDetectProjectError(current, body as AddProjectApiErrorBody)
      )
    } catch {
      setState((current) => ({
        ...current,
        errorMessage: "Could not reach the local folder browser.",
      }))
    } finally {
      setIsBrowsing(false)
    }
  }

  async function saveProject(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsSaving(true)

    try {
      const response = await fetch("/api/projects", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          repoPath: state.repoPath,
          key: state.key,
          displayName: state.displayName,
        }),
      })
      const body = (await response.json()) as
        | CreateProjectSuccessBody
        | AddProjectApiErrorBody

      if (response.ok && "route" in body) {
        router.push(body.route.projectPath)
        return
      }

      setState((current) =>
        applyCreateProjectError(current, body as AddProjectApiErrorBody)
      )
    } catch {
      setState((current) => ({
        ...current,
        errorMessage: "Could not reach the local Project creation API.",
      }))
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <form
      onSubmit={saveProject}
      className="w-full max-w-3xl"
    >
      <section className="min-w-0 rounded-lg border bg-card p-5 shadow-sm">
        <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="text-xl font-semibold tracking-normal">
              Add Project
            </h2>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              Connect Operator to a local Git checkout.
            </p>
          </div>
        </div>

        <div className="grid gap-4">
          <label className="grid gap-1.5">
            <span className="text-sm font-medium">Repository path</span>
            <div className="flex min-w-0 flex-col gap-2 sm:flex-row">
              <input
                value={state.repoPath}
                onChange={(event) =>
                  setState((current) =>
                    applyRepositoryPathChange(current, event.target.value)
                  )
                }
                className="h-9 min-w-0 flex-1 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
                placeholder="/Users/example/workspace/repo"
              />
              <div className="flex shrink-0 gap-2">
                <Button
                  type="button"
                  variant="outline"
                  onClick={browseProjectPath}
                  disabled={isBrowsing}
                  title="Browse"
                >
                  <FolderOpen data-icon="inline-start" />
                  Browse
                </Button>
              </div>
            </div>
          </label>

          <div className="grid gap-4 sm:grid-cols-2">
            <label className="grid gap-1.5">
              <span className="text-sm font-medium">Project key</span>
              <input
                value={state.key}
                onChange={(event) =>
                  setState((current) =>
                    applyProjectKeyChange(current, event.target.value)
                  )
                }
                className="h-9 rounded-md border bg-background px-3 font-mono text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
                placeholder="operator"
                maxLength={32}
              />
            </label>
            <label className="grid gap-1.5">
              <span className="text-sm font-medium">Display name</span>
              <input
                value={state.displayName}
                onChange={(event) =>
                  setState((current) => ({
                    ...current,
                    displayName: event.target.value,
                  }))
                }
                className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
                placeholder="Operator"
              />
            </label>
          </div>

          {state.errorMessage ? (
            <div
              role="alert"
              className="rounded-lg border border-destructive/35 bg-destructive/10 px-3 py-2 text-sm text-destructive"
            >
              {state.errorMessage}
            </div>
          ) : null}

          <div className="flex justify-end">
            <Button
              type="submit"
              disabled={!canSubmitAddProjectForm(state, isSaving)}
              title="Save Project"
            >
              <Save data-icon="inline-start" />
              Save Project
            </Button>
          </div>
        </div>
      </section>
    </form>
  )
}
