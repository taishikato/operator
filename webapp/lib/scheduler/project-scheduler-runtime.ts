import { createProjectRepository } from "../projects/project-repository.ts"
import { createRunOrchestrator } from "../runs/run-orchestration.ts"
import { createTaskRepository } from "../tasks/task-repository.ts"
import { createProjectBatchRunner } from "./project-batch-runner.ts"
import { createProjectScheduler } from "./project-scheduler.ts"

type Scheduler = {
  tick(now?: Date): Promise<unknown>
}

type IntervalHandle = ReturnType<typeof setInterval> | number

export type ProjectSchedulerRuntime = ReturnType<
  typeof createProjectSchedulerRuntime
>

let appRuntime: ProjectSchedulerRuntime | null = null

export function ensureProjectSchedulerRuntimeStarted({
  databasePath,
  cursorApiKey,
}: {
  databasePath: string
  cursorApiKey?: string
}) {
  if (appRuntime) {
    return appRuntime
  }

  const projects = createProjectRepository({ databasePath })
  const tasks = createTaskRepository({ databasePath })
  const runs = createRunOrchestrator({
    databasePath,
    cursorApiKey: cursorApiKey ?? process.env.CURSOR_API_KEY,
  })
  const runtime = createProjectSchedulerRuntime({
    scheduler: createProjectScheduler({
      projects,
      batches: createProjectBatchRunner({ tasks, runs }),
    }),
  })

  runtime.start()
  appRuntime = runtime
  return runtime
}

export function createProjectSchedulerRuntime({
  scheduler,
  intervalMs = 60_000,
  setInterval: scheduleInterval = globalThis.setInterval,
  clearInterval: cancelInterval = globalThis.clearInterval,
  onError = (error) => console.error(error),
}: {
  scheduler: Scheduler
  intervalMs?: number
  setInterval?: (
    callback: () => void | Promise<void>,
    intervalMs: number
  ) => IntervalHandle
  clearInterval?: (handle: IntervalHandle) => void
  onError?: (error: unknown) => void
}) {
  let interval: IntervalHandle | null = null
  let isTicking = false

  async function tick() {
    if (isTicking) {
      return
    }

    isTicking = true

    try {
      await scheduler.tick()
    } catch (error) {
      onError(error)
    } finally {
      isTicking = false
    }
  }

  return {
    start() {
      if (interval) {
        return
      }

      void tick()
      interval = scheduleInterval(() => void tick(), intervalMs)
      if (typeof interval === "object" && "unref" in interval) {
        interval.unref?.()
      }
    },
    stop() {
      if (!interval) {
        return
      }

      cancelInterval(interval)
      interval = null
    },
    isStarted() {
      return interval !== null
    },
  }
}
