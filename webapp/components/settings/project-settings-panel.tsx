"use client"

import { Monitor, Moon, Sun } from "lucide-react"
import { useTheme } from "next-themes"
import { useState } from "react"

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

  return (
    <div className="grid gap-4">
      <div
        role="tablist"
        aria-label="Settings sections"
        className="inline-flex w-fit rounded-md border bg-muted/25 p-0.5"
      >
        <button
          type="button"
          role="tab"
          aria-selected={activeTab === "project"}
          onClick={() => setActiveTab("project")}
          className={`h-8 rounded px-3 text-sm font-medium transition ${
            activeTab === "project"
              ? "bg-background shadow-sm"
              : "text-muted-foreground"
          }`}
        >
          Project
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={activeTab === "app"}
          onClick={() => setActiveTab("app")}
          className={`h-8 rounded px-3 text-sm font-medium transition ${
            activeTab === "app"
              ? "bg-background shadow-sm"
              : "text-muted-foreground"
          }`}
        >
          App
        </button>
      </div>

      {activeTab === "project" ? (
        <ProjectSettingsForm projectKey={projectKey} project={project} />
      ) : (
        <AppSettingsStatus appStatus={appStatus} />
      )}
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
