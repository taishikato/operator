import type { RunTaskNowResult } from "../runs/run-orchestration.ts"

type ReadyTask = {
  displayId: string
}

type TaskSelectionRepository = {
  listReadyTasksForRunSelection(projectId: string): Promise<ReadyTask[]>
}

type RunTaskNow = {
  runTaskNow(input: {
    projectKey: string
    taskDisplayId: string
  }): Promise<RunTaskNowResult>
}

export type ProjectBatchResult = {
  status: "completed" | "stopped" | "already_running"
  results: RunTaskNowResult[]
}

const activeProjectIds = new Set<string>()

export function createProjectBatchRunner({
  tasks,
  runs,
}: {
  tasks: TaskSelectionRepository
  runs: RunTaskNow
}) {
  return {
    async runReadyTaskBatch({
      projectId,
      projectKey,
      limit,
    }: {
      projectId: string
      projectKey: string
      limit: number
    }): Promise<ProjectBatchResult> {
      if (activeProjectIds.has(projectId)) {
        return { status: "already_running", results: [] }
      }

      activeProjectIds.add(projectId)

      try {
        const readyTasks = await tasks.listReadyTasksForRunSelection(projectId)
        const results: RunTaskNowResult[] = []

        for (const task of readyTasks.slice(0, limit)) {
          const result = await runs.runTaskNow({
            projectKey,
            taskDisplayId: task.displayId,
          })
          results.push(result)

          if (result.status !== "review") {
            return { status: "stopped", results }
          }
        }

        return { status: "completed", results }
      } finally {
        activeProjectIds.delete(projectId)
      }
    },
  }
}
