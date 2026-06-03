"use client"

import { RotateCcw, Save } from "lucide-react"
import { useRouter } from "next/navigation"
import { useState } from "react"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"

export type ProjectSettingsFormValue = {
  defaults: {
    model: string
    reasoningLevel: string
    runTimeoutSeconds: number
  }
  schedule: {
    enabled: boolean
    dailyTime: string
    timezone: string
    scheduledRunLimit: number
  }
}

type ProjectSettingsResponse =
  | {
      project: ProjectSettingsFormValue
    }
  | {
      error?: {
        message?: string
      }
    }

type ProjectSettingsDraft = {
  defaultModel: string
  defaultReasoningLevel: string
  scheduleEnabled: boolean
  scheduleDailyTime: string
  scheduleTimezone: string
  scheduledRunLimit: string
  runTimeoutSeconds: string
}

export function ProjectSettingsForm({
  projectKey,
  project,
}: {
  projectKey: string
  project: ProjectSettingsFormValue
}) {
  const router = useRouter()
  const [saved, setSaved] = useState(() => toDraft(project))
  const [draft, setDraft] = useState(() => toDraft(project))
  const [isSaving, setIsSaving] = useState(false)
  const hasChanges = JSON.stringify(saved) !== JSON.stringify(draft)

  function updateDraft(patch: Partial<ProjectSettingsDraft>) {
    setDraft((current) => ({ ...current, ...patch }))
  }

  async function saveSettings() {
    setIsSaving(true)

    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(projectKey)}/settings`,
        {
          method: "PATCH",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(toPayload(draft)),
        }
      )
      const body = (await response.json()) as ProjectSettingsResponse

      if (response.ok && "project" in body) {
        const next = toDraft(body.project)
        setSaved(next)
        setDraft(next)
        toast.success("Project settings saved.")
        router.refresh()
        return
      }

      toast.error(getErrorMessage(body, "Could not save Project settings."))
    } catch {
      toast.error("Could not reach the local Project settings API.")
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <section className="grid gap-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Default model
          </span>
          <input
            value={draft.defaultModel}
            onChange={(event) =>
              updateDraft({ defaultModel: event.target.value })
            }
            onInput={(event) =>
              updateDraft({
                defaultModel: (event.currentTarget as HTMLInputElement).value,
              })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>

        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Default reasoning
          </span>
          <select
            value={draft.defaultReasoningLevel}
            onChange={(event) =>
              updateDraft({ defaultReasoningLevel: event.target.value })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <option value="low">low</option>
            <option value="medium">medium</option>
            <option value="high">high</option>
          </select>
        </label>

        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Daily time
          </span>
          <input
            value={draft.scheduleDailyTime}
            onChange={(event) =>
              updateDraft({ scheduleDailyTime: event.target.value })
            }
            onInput={(event) =>
              updateDraft({
                scheduleDailyTime: (event.currentTarget as HTMLInputElement)
                  .value,
              })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>

        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Timezone
          </span>
          <input
            value={draft.scheduleTimezone}
            onChange={(event) =>
              updateDraft({ scheduleTimezone: event.target.value })
            }
            onInput={(event) =>
              updateDraft({
                scheduleTimezone: (event.currentTarget as HTMLInputElement)
                  .value,
              })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>

        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Scheduled run limit
          </span>
          <input
            type="number"
            min={1}
            max={100}
            value={draft.scheduledRunLimit}
            onChange={(event) =>
              updateDraft({ scheduledRunLimit: event.target.value })
            }
            onInput={(event) =>
              updateDraft({
                scheduledRunLimit: (event.currentTarget as HTMLInputElement)
                  .value,
              })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>

        <label className="grid gap-1.5">
          <span className="text-xs font-medium text-muted-foreground">
            Run timeout seconds
          </span>
          <input
            type="number"
            min={60}
            value={draft.runTimeoutSeconds}
            onChange={(event) =>
              updateDraft({ runTimeoutSeconds: event.target.value })
            }
            onInput={(event) =>
              updateDraft({
                runTimeoutSeconds: (event.currentTarget as HTMLInputElement)
                  .value,
              })
            }
            disabled={isSaving}
            className="h-9 rounded-md border bg-background px-3 text-sm transition outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:cursor-not-allowed disabled:opacity-50"
          />
        </label>
      </div>

      <label className="inline-flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={draft.scheduleEnabled}
          onChange={(event) =>
            updateDraft({ scheduleEnabled: event.target.checked })
          }
          disabled={isSaving}
          className="h-4 w-4 rounded border"
        />
        Schedule enabled
      </label>

      <div className="flex flex-wrap items-center justify-end gap-2 border-t pt-4">
        <Button
          type="button"
          variant="outline"
          onClick={() => setDraft(saved)}
          disabled={isSaving || !hasChanges}
          title="Discard changes"
        >
          <RotateCcw data-icon="inline-start" />
          Discard
        </Button>
        <Button
          type="button"
          onClick={saveSettings}
          disabled={isSaving || !hasChanges}
          title="Save Project settings"
        >
          <Save data-icon="inline-start" />
          Save
        </Button>
      </div>
    </section>
  )
}

function toDraft(project: ProjectSettingsFormValue): ProjectSettingsDraft {
  return {
    defaultModel: project.defaults.model,
    defaultReasoningLevel: project.defaults.reasoningLevel,
    scheduleEnabled: project.schedule.enabled,
    scheduleDailyTime: project.schedule.dailyTime,
    scheduleTimezone: project.schedule.timezone,
    scheduledRunLimit: String(project.schedule.scheduledRunLimit),
    runTimeoutSeconds: String(project.defaults.runTimeoutSeconds),
  }
}

function toPayload(draft: ProjectSettingsDraft) {
  return {
    defaultModel: draft.defaultModel,
    defaultReasoningLevel: draft.defaultReasoningLevel,
    scheduleEnabled: draft.scheduleEnabled,
    scheduleDailyTime: draft.scheduleDailyTime,
    scheduleTimezone: draft.scheduleTimezone,
    scheduledRunLimit: Number(draft.scheduledRunLimit),
    runTimeoutSeconds: Number(draft.runTimeoutSeconds),
  }
}

function getErrorMessage(body: ProjectSettingsResponse, fallback: string) {
  return "error" in body ? body.error?.message ?? fallback : fallback
}
