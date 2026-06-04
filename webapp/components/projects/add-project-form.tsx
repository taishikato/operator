"use client"

import {
  FolderOpen,
  GitBranch,
  GitFork,
  PackageCheck,
  Save,
  Search,
} from "lucide-react"
import { useRouter } from "next/navigation"
import type { FormEvent, ReactNode } from "react"
import { useState } from "react"

import { Button } from "@/components/ui/button"
import {
  applyCreateProjectError,
  applyDetectProjectError,
  applyDetectProjectSuccess,
  applyProjectKeyChange,
  applyRepositoryPathChange,
  createInitialAddProjectFormState,
  type AddProjectApiErrorBody,
  type DetectProjectSuccessBody,
} from "@/lib/projects/add-project-ui-state"

type CreateProjectSuccessBody = {
  route: {
    projectPath: string
  }
}

export function AddProjectForm() {
  const router = useRouter()
  const [state, setState] = useState(createInitialAddProjectFormState)
  const [isDetecting, setIsDetecting] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [isBrowsing, setIsBrowsing] = useState(false)

  async function detectProject() {
    setIsDetecting(true)

    try {
      const response = await fetch("/api/projects/detect", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ repoPath: state.repoPath }),
      })
      const body = (await response.json()) as
        | DetectProjectSuccessBody
        | AddProjectApiErrorBody

      setState((current) =>
        response.ok
          ? applyDetectProjectSuccess(
              { ...current, repoPath: state.repoPath },
              body as DetectProjectSuccessBody
            )
          : applyDetectProjectError(current, body as AddProjectApiErrorBody)
      )
    } catch {
      setState((current) => ({
        ...current,
        errorMessage: "Could not reach the local Project detection API.",
      }))
    } finally {
      setIsDetecting(false)
    }
  }

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
      className="grid w-full gap-5 lg:grid-cols-[minmax(0,1fr)_360px]"
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
                <Button
                  type="button"
                  onClick={detectProject}
                  disabled={isDetecting || state.repoPath.trim().length === 0}
                  title="Detect repository"
                >
                  <Search data-icon="inline-start" />
                  Detect
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
                className="h-9 rounded-md border bg-background px-3 font-mono text-sm uppercase transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40"
                placeholder="OP"
                maxLength={6}
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
              disabled={
                isSaving ||
                !state.repositoryPreview ||
                state.key.trim().length === 0 ||
                state.displayName.trim().length === 0
              }
              title="Save Project"
            >
              <Save data-icon="inline-start" />
              Save Project
            </Button>
          </div>
        </div>
      </section>

      <RepositoryPreview state={state} />
    </form>
  )
}

function RepositoryPreview({
  state,
}: {
  state: ReturnType<typeof createInitialAddProjectFormState>
}) {
  if (!state.repositoryPreview) {
    return (
      <aside className="rounded-lg border bg-muted/35 p-5 text-sm text-muted-foreground">
        Repository metadata appears here after detection.
      </aside>
    )
  }

  const repository = state.repositoryPreview

  return (
    <aside className="rounded-lg border bg-card p-5 shadow-sm">
      <h2 className="text-sm font-semibold">Detected metadata</h2>
      <dl className="mt-4 grid gap-3 text-sm">
        <PreviewRow label="Repository" value={repository.name} />
        <PreviewRow label="Path" value={repository.path} mono />
        <PreviewRow
          label="Default branch"
          value={repository.defaultBranch ?? "Not detected"}
          icon={<GitBranch />}
        />
        <PreviewRow
          label="GitHub"
          value={repository.githubSlug ?? "Not detected"}
          icon={<GitFork />}
        />
        <PreviewRow
          label="Packages"
          value={
            repository.packageManagers.length > 0
              ? repository.packageManagers.join(", ")
              : "None detected"
          }
          icon={<PackageCheck />}
        />
        <PreviewRow
          label="Instructions"
          value={
            repository.instructionFiles.length > 0
              ? repository.instructionFiles.join(", ")
              : "None detected"
          }
        />
      </dl>
    </aside>
  )
}

function PreviewRow({
  icon,
  label,
  mono = false,
  value,
}: {
  icon?: ReactNode
  label: string
  mono?: boolean
  value: string
}) {
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
        {icon ? <span className="[&_svg]:size-3.5">{icon}</span> : null}
        {label}
      </dt>
      <dd
        className={
          mono
            ? "mt-0.5 font-mono text-xs break-all"
            : "mt-0.5 text-sm break-words"
        }
      >
        {value}
      </dd>
    </div>
  )
}
