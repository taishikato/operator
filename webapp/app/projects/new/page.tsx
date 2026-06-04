import { AddProjectForm } from "@/components/projects/add-project-form"
import { resolveAddProjectApiOptions } from "@/lib/projects/add-project-api"

export const dynamic = "force-dynamic"

export default async function NewProjectPage() {
  const { databaseStatus } = await resolveAddProjectApiOptions()

  return (
    <main className="min-h-svh bg-background px-4 py-6 sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-5xl flex-col gap-5">
        <header className="flex min-w-0 flex-col gap-1 border-b pb-4">
          <p className="text-sm font-medium text-muted-foreground">Operator</p>
          <h1 className="text-xl font-semibold tracking-normal">
            Add Project
          </h1>
          <p className="max-w-3xl text-sm text-muted-foreground">
            Add another local Git repository workspace.
          </p>
        </header>

        {databaseStatus === "requires_explicit_apply" ? (
          <div
            role="alert"
            className="rounded-lg border border-amber-500/35 bg-amber-500/10 p-4 text-sm text-amber-950 dark:text-amber-100"
          >
            Operator database schema is out of date. Run the explicit database
            apply command or reset the local Operator database.
          </div>
        ) : (
          <AddProjectForm />
        )}
      </div>
    </main>
  )
}
