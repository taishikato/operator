"use client"

import { Monitor, Moon, Sun } from "lucide-react"
import { useTheme } from "next-themes"
import { type KeyboardEvent, useRef, useState } from "react"

import {
  ProjectSettingsForm,
  type ProjectSettingsFormValue,
} from "@/components/settings/project-settings-form"
import { Button } from "@/components/ui/button"
import type { AppOperationalStatus } from "@/lib/settings/app-operational-status"

type SettingsTab = "project" | "app"

export function ProjectSettingsPanel({
  projectKey,
  project,
  appStatus,
}: {
  projectKey: string
  project: ProjectSettingsFormValue
  appStatus: AppOperationalStatus
}) {
  const [activeTab, setActiveTab] = useState<SettingsTab>("project")
  const projectTabRef = useRef<HTMLButtonElement>(null)
  const appTabRef = useRef<HTMLButtonElement>(null)

  function selectTab(nextTab: SettingsTab) {
    setActiveTab(nextTab)
    if (nextTab === "project") {
      projectTabRef.current?.focus()
      return
    }
    appTabRef.current?.focus()
  }

  function handleTabKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "ArrowRight" || event.key === "End") {
      event.preventDefault()
      selectTab("app")
      return
    }

    if (event.key === "ArrowLeft" || event.key === "Home") {
      event.preventDefault()
      selectTab("project")
    }
  }

  return (
    <div className="grid gap-4">
      <div
        role="tablist"
        aria-label="Settings sections"
        className="inline-flex w-fit rounded-md border bg-muted/25 p-0.5"
      >
        <button
          ref={projectTabRef}
          id="project-tab"
          type="button"
          role="tab"
          aria-controls="project-settings-tab"
          aria-selected={activeTab === "project"}
          tabIndex={activeTab === "project" ? 0 : -1}
          onClick={() => selectTab("project")}
          onKeyDown={handleTabKeyDown}
          className={`h-8 rounded px-3 text-sm font-medium transition ${
            activeTab === "project"
              ? "bg-background shadow-sm"
              : "text-muted-foreground"
          }`}
        >
          Project
        </button>
        <button
          ref={appTabRef}
          id="app-tab"
          type="button"
          role="tab"
          aria-controls="app-settings-tab"
          aria-selected={activeTab === "app"}
          tabIndex={activeTab === "app" ? 0 : -1}
          onClick={() => selectTab("app")}
          onKeyDown={handleTabKeyDown}
          className={`h-8 rounded px-3 text-sm font-medium transition ${
            activeTab === "app"
              ? "bg-background shadow-sm"
              : "text-muted-foreground"
          }`}
        >
          App
        </button>
      </div>

      <div
        id="project-settings-tab"
        role="tabpanel"
        aria-labelledby="project-tab"
        hidden={activeTab !== "project"}
      >
        <ProjectSettingsForm projectKey={projectKey} project={project} />
      </div>
      <div
        id="app-settings-tab"
        role="tabpanel"
        aria-labelledby="app-tab"
        hidden={activeTab !== "app"}
      >
        <AppSettingsStatus appStatus={appStatus} />
      </div>
    </div>
  )
}

function AppSettingsStatus({
  appStatus,
}: {
  appStatus: AppOperationalStatus
}) {
  return (
    <section className="grid gap-5">
      <dl className="grid gap-3 sm:grid-cols-3">
        <StatusItem label="App data directory" value={appStatus.appDataDir} />
        <StatusItem
          label="Cursor API key"
          value={appStatus.cursorApiKeyStatus}
        />
        <StatusItem label="Operator version" value={appStatus.version} />
      </dl>

      <ThemeControls />
    </section>
  )
}

function StatusItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0 rounded-md border bg-card p-3">
      <dt className="text-xs font-medium text-muted-foreground">{label}</dt>
      <dd className="mt-1 truncate font-mono text-sm">{value}</dd>
    </div>
  )
}

function ThemeControls() {
  const { theme, setTheme } = useTheme()

  return (
    <section className="grid gap-2">
      <h2 className="text-sm font-semibold">Theme</h2>
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          variant={theme === "system" ? "default" : "outline"}
          onClick={() => setTheme("system")}
          title="Use system theme"
        >
          <Monitor data-icon="inline-start" />
          System
        </Button>
        <Button
          type="button"
          variant={theme === "light" ? "default" : "outline"}
          onClick={() => setTheme("light")}
          title="Use light theme"
        >
          <Sun data-icon="inline-start" />
          Light
        </Button>
        <Button
          type="button"
          variant={theme === "dark" ? "default" : "outline"}
          onClick={() => setTheme("dark")}
          title="Use dark theme"
        >
          <Moon data-icon="inline-start" />
          Dark
        </Button>
      </div>
    </section>
  )
}
