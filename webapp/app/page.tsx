import { redirect } from "next/navigation"

import { AddProjectForm } from "@/components/projects/add-project-form"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"
import { createProjectRepository } from "@/lib/projects/project-repository"
import { loadInitialProjectRoute } from "@/lib/projects/project-routing"

export const dynamic = "force-dynamic"

export default async function Page() {
  const { databasePath } = await resolveAddProjectApiOptions()
  const projectRoute = await loadInitialProjectRoute(
    createProjectRepository({ databasePath })
  )

  if (projectRoute) {
    redirect(projectRoute)
  }

  return (
    <main className="min-h-svh bg-background px-4 py-6 sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
        <header className="flex min-w-0 flex-col gap-1 border-b pb-4">
          <p className="text-sm font-medium text-muted-foreground">Operator</p>
          <p className="max-w-3xl text-sm text-muted-foreground">
            Add a local Git repository to create the first Project workspace.
          </p>
        </header>
        <AddProjectForm />
      </div>
    </main>
  )
}
