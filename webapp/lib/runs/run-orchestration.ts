import { connect } from "@tursodatabase/database"
import { existsSync } from "node:fs"
import { spawnSync } from "node:child_process"
import { dirname } from "node:path"
import { and, eq, isNull, lt, sql } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { ulid } from "ulid"

import {
  resolveAppDataPaths,
  type AppDataPaths,
} from "../app-data/app-data.ts"
import { runs, tasks as taskRows } from "../db/schema.ts"
import { createProjectRepository } from "../projects/project-repository.ts"
import {
  createTaskRepository,
  type Task,
  type TaskStatus,
} from "../tasks/task-repository.ts"
import {
  appendRunLogEvent,
  createRawRunLogKey,
} from "./raw-log.ts"

export type RunBlockedReason =
  | "dirty_worktree"
  | "worktree_dirty_no_commit"
  | "no_commit_created"
  | "dirty_after_commit"
  | "interrupted"
  | "agent_error"
  | "canceled"
  | "timeout"
  | "git_error"
  | "missing_cursor_api_key"
  | "repository_not_found"
  | "task_not_runnable"
  | "model_missing"

export type RunTaskNowResult = {
  status: "review" | "blocked"
  blockedReason: RunBlockedReason | null
  taskBranchName: string
  runId: string | null
}

export type CursorRunAdapter = {
  run(input: {
    apiKey: string
    branchName: string
    model: string
    prompt: string
    reasoningLevel: string
    repoPath: string
    timeoutSeconds: number
    abortSignal: AbortSignal
    onEvent: (event: unknown) => Promise<void>
  }): Promise<{ adapterRunId?: string | null }>
}

export type GitRunAdapter = {
  repositoryExists(): Promise<boolean>
  isGitRepository(): Promise<boolean>
  getCurrentBranch(): Promise<string | null>
  isWorktreeClean(): Promise<boolean>
  getHeadSha(): Promise<string>
  checkoutOrCreateBranch(branchName: string, baseBranch: string): Promise<void>
}

export type CreateRunOrchestratorOptions = {
  databasePath: string
  appDataPaths?: AppDataPaths
  cursorApiKey?: string
  cursorAdapter?: CursorRunAdapter
  gitAdapter?: GitRunAdapter
}

type RunRecordInput = {
  runId: string
  rawLogKey: string
  projectId: string
  taskId: string
  taskDisplayId: string
  taskBranchName: string
  model: string
  reasoningLevel: string
  baseBranch: string
  headBefore: string
  worktreeDirtyBefore: boolean
}

type FinishRunInput = {
  status: "review" | "blocked"
  blockedReason: RunBlockedReason | null
  headAfter: string | null
  worktreeDirtyAfter: boolean | null
  adapterRunId?: string | null
}

type CreatedRun = {
  runId: string
  rawLogKey: string
}

type RunDb = ReturnType<
  typeof drizzle<{ runs: typeof runs; tasks: typeof taskRows }>
>

type CursorSdkModule = {
  Agent: {
    create(input: {
      apiKey: string
      model: { id: string }
      local: { cwd: string }
    }): Promise<{
      send(prompt: string): Promise<{
        id?: string
        stream(): AsyncIterable<unknown>
        cancel(): Promise<void>
      }>
    }>
  }
}

export class CursorRunTimeoutError extends Error {
  override name = "CursorRunTimeoutError"
}

const RUNNABLE_TASK_STATUSES = new Set<TaskStatus>([
  "backlog",
  "ready",
  "blocked",
  "review",
])

export function canRunTaskNow(status: string): status is TaskStatus {
  return RUNNABLE_TASK_STATUSES.has(status as TaskStatus)
}

export function classifyRunResult({
  headBefore,
  headAfter,
  cleanAfter,
}: {
  headBefore: string
  headAfter: string
  cleanAfter: boolean
}): {
  status: "review" | "blocked"
  blockedReason: RunBlockedReason | null
} {
  const hasCommitDelta = headBefore !== headAfter

  if (hasCommitDelta && cleanAfter) {
    return { status: "review", blockedReason: null }
  }

  if (!hasCommitDelta && !cleanAfter) {
    return { status: "blocked", blockedReason: "worktree_dirty_no_commit" }
  }

  if (!hasCommitDelta && cleanAfter) {
    return { status: "blocked", blockedReason: "no_commit_created" }
  }

  return { status: "blocked", blockedReason: "dirty_after_commit" }
}

export function buildCursorRunPrompt({
  projectKey,
  projectName,
  repoPath,
  branchName,
  task,
  checks,
}: {
  projectKey: string
  projectName: string
  repoPath: string
  branchName: string
  task: Pick<
    Task,
    "displayId" | "title" | "bodyMarkdown" | "acceptanceCriteriaMarkdown"
  >
  checks: string[]
}) {
  return [
    `You are working on Project ${projectKey}: ${projectName}.`,
    `Repository: ${repoPath}`,
    "",
    `Task ${task.displayId}: ${task.title}`,
    "",
    "Task body:",
    task.bodyMarkdown.trim() || "(empty)",
    "",
    "Acceptance criteria:",
    task.acceptanceCriteriaMarkdown.trim() || "(empty)",
    "",
    "Branch constraints:",
    `- The current branch must remain ${branchName}.`,
    "- Do not switch to another branch unless explicitly required to inspect history, and return before making changes.",
    "",
    "Completion requirements:",
    "- Implement only this Task's scope.",
    `- Run these checks before finishing: ${checks.join(", ")}.`,
    "- Commit the completed work locally.",
    "- Commit message must be in English.",
    "- Do not push.",
  ].join("\n")
}

const reconciledDatabasePaths = new Set<string>()

export function resetStaleRunReconciliationForTests() {
  reconciledDatabasePaths.clear()
}

export async function reconcileStaleRunsOnStartup(databasePath: string) {
  return createRunOrchestrator({ databasePath }).reconcileInterruptedRuns({
    interruptedBefore: new Date(),
  })
}

export async function ensureStaleRunsReconciled(databasePath: string) {
  if (reconciledDatabasePaths.has(databasePath)) {
    return { interruptedRuns: 0 }
  }

  const result = await reconcileStaleRunsOnStartup(databasePath)
  reconciledDatabasePaths.add(databasePath)
  return result
}

export function createRunOrchestrator(options: CreateRunOrchestratorOptions) {
  const appDataPaths =
    options.appDataPaths ??
    resolveAppDataPaths({ appDataRoot: dirname(options.databasePath) })

  return {
    async runTaskNow({
      projectKey,
      taskDisplayId,
    }: {
      projectKey: string
      taskDisplayId: string
    }): Promise<RunTaskNowResult> {
      const projects = createProjectRepository({
        databasePath: options.databasePath,
      })
      const tasks = createTaskRepository({ databasePath: options.databasePath })
      const project = await projects.getActiveProjectByKey(projectKey)

      if (!project) {
        return blockedWithoutRun("repository_not_found", "")
      }

      const task = await tasks.getActiveTaskByDisplayId(taskDisplayId)

      if (!task || task.projectId !== project.id) {
        return blockedWithoutRun("task_not_runnable", "")
      }

      if (!canRunTaskNow(task.status)) {
        return blockedWithoutRun(
          "task_not_runnable",
          task.taskBranchName ?? ""
        )
      }

      const generatedBranchName = generateTaskBranchName({
        projectKey: project.key,
        taskNumber: task.number,
        title: task.title,
      })
      const taskBranchName = await tasks.setTaskBranchName(
        task.id,
        generatedBranchName
      )

      if (!options.cursorApiKey) {
        await tasks.markTaskBlocked(task.id, "missing_cursor_api_key")
        return blockedWithoutRun("missing_cursor_api_key", taskBranchName)
      }

      const cursorApiKey = options.cursorApiKey
      const model = task.modelOverride ?? project.defaults.model
      const reasoningLevel =
        task.reasoningLevelOverride ?? project.defaults.reasoningLevel

      if (!model || !reasoningLevel) {
        await tasks.markTaskBlocked(task.id, "model_missing")
        return blockedWithoutRun("model_missing", taskBranchName)
      }

      const git =
        options.gitAdapter ?? createLocalGitRunAdapter(project.repoPath)

      let headBefore: string
      const baseBranch = project.repositoryMetadata.defaultBranch

      try {
        if (!(await git.repositoryExists())) {
          await tasks.markTaskBlocked(task.id, "repository_not_found")
          return blockedWithoutRun("repository_not_found", taskBranchName)
        }

        if (!(await git.isGitRepository())) {
          await tasks.markTaskBlocked(task.id, "git_error")
          return blockedWithoutRun("git_error", taskBranchName)
        }

        const currentBranch = await git.getCurrentBranch()

        if (!baseBranch || !currentBranch) {
          await tasks.markTaskBlocked(task.id, "git_error")
          return blockedWithoutRun("git_error", taskBranchName)
        }

        if (!(await git.isWorktreeClean())) {
          await tasks.markTaskBlocked(task.id, "dirty_worktree")
          return blockedWithoutRun("dirty_worktree", taskBranchName)
        }

        await git.checkoutOrCreateBranch(taskBranchName, baseBranch)
        headBefore = await git.getHeadSha()
      } catch (error) {
        void error
        await tasks.markTaskBlocked(task.id, "git_error")
        return blockedWithoutRun("git_error", taskBranchName)
      }

      if (!(await tasks.tryClaimTaskForRun(task.id))) {
        return blockedWithoutRun("task_not_runnable", taskBranchName)
      }

      const runId = ulid()
      const rawLogKey = createRawRunLogKey(runId)
      const run = await insertRun(options.databasePath, {
        runId,
        rawLogKey,
        projectId: project.id,
        taskId: task.id,
        taskDisplayId: task.displayId,
        taskBranchName,
        model,
        reasoningLevel,
        baseBranch,
        headBefore,
        worktreeDirtyBefore: false,
      })
      await appendOperatorRunLog(appDataPaths, run, "run.created", {
        projectKey: project.key,
        taskDisplayId: task.displayId,
        taskBranchName,
      })
      await appendOperatorRunLog(appDataPaths, run, "git.preflight.completed", {
        baseBranch,
        headBefore,
        taskBranchName,
      })

      try {
        const cursor = options.cursorAdapter ?? createCursorSdkRunAdapter()
        const adapterResult = await runCursorAdapterWithTimeout(
          (abortSignal) =>
            cursor.run({
              apiKey: cursorApiKey,
              branchName: taskBranchName,
              model,
              prompt: buildCursorRunPrompt({
                projectKey: project.key,
                projectName: project.displayName,
                repoPath: project.repoPath,
                branchName: taskBranchName,
                task,
                checks: [
                  "pnpm test",
                  "pnpm typecheck",
                  "pnpm lint",
                  "pnpm build",
                ],
              }),
              reasoningLevel,
              repoPath: project.repoPath,
              timeoutSeconds: project.defaults.runTimeoutSeconds,
              abortSignal,
              onEvent: (event) =>
                appendCursorRunLogEvent(appDataPaths, run.rawLogKey, event),
            }),
          project.defaults.runTimeoutSeconds
        )

        let headAfter: string | null = null
        let cleanAfter: boolean | null = null

        try {
          headAfter = await git.getHeadSha()
          cleanAfter = await git.isWorktreeClean()
        } catch (postRunGitError) {
          void postRunGitError
          await finishRun(options.databasePath, runId, {
            status: "blocked",
            blockedReason: "git_error",
            headAfter,
            worktreeDirtyAfter:
              cleanAfter === null ? null : !cleanAfter,
            adapterRunId: adapterResult.adapterRunId,
          })
          await appendOperatorRunLog(appDataPaths, run, "run.finished", {
            status: "blocked",
            blockedReason: "git_error",
          })
          await tasks.markTaskBlocked(task.id, "git_error")

          return {
            status: "blocked",
            blockedReason: "git_error",
            taskBranchName,
            runId,
          }
        }

        const classification = classifyRunResult({
          headBefore,
          headAfter,
          cleanAfter,
        })

        await finishRun(options.databasePath, runId, {
          ...classification,
          headAfter,
          worktreeDirtyAfter: !cleanAfter,
          adapterRunId: adapterResult.adapterRunId,
        })
        await appendOperatorRunLog(appDataPaths, run, "run.finished", {
          status: classification.status,
          blockedReason: classification.blockedReason,
          headAfter,
          worktreeDirtyAfter: !cleanAfter,
        })

        if (classification.status === "review") {
          await tasks.markTaskReview(task.id)
        } else {
          await tasks.markTaskBlocked(
            task.id,
            classification.blockedReason ?? "agent_error"
          )
        }

        return {
          ...classification,
          taskBranchName,
          runId,
        }
      } catch (error) {
        void error
        const blockedReason: RunBlockedReason =
          error instanceof CursorRunTimeoutError ? "timeout" : "agent_error"

        await finishRun(options.databasePath, runId, {
          status: "blocked",
          blockedReason,
          headAfter: null,
          worktreeDirtyAfter: null,
        })
        await appendOperatorRunLog(appDataPaths, run, "run.finished", {
          status: "blocked",
          blockedReason,
        })
        await tasks.markTaskBlocked(task.id, blockedReason)

        return {
          status: "blocked",
          blockedReason,
          taskBranchName,
          runId,
        }
      }
    },

    async reconcileInterruptedRuns({
      interruptedBefore,
    }: {
      interruptedBefore: Date
    }) {
      const interruptedRuns = await markInterruptedRuns(
        options.databasePath,
        interruptedBefore.toISOString()
      )

      return { interruptedRuns }
    },
  }
}

export function generateTaskBranchName({
  projectKey,
  taskNumber,
  title,
}: {
  projectKey: string
  taskNumber: number
  title: string
}) {
  return `operator/${projectKey.toLowerCase()}-${taskNumber}-${slugTitle(title)}`
}

function slugTitle(title: string) {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48)
    .replace(/-+$/g, "")

  return slug || "task"
}

function blockedWithoutRun(
  blockedReason: RunBlockedReason,
  taskBranchName: string
): RunTaskNowResult {
  return {
    status: "blocked",
    blockedReason,
    taskBranchName,
    runId: null,
  }
}

async function insertRun(databasePath: string, input: RunRecordInput) {
  const now = new Date().toISOString()

  await withRunDb(databasePath, async (db) => {
    await db.insert(runs).values({
      id: input.runId,
      projectId: input.projectId,
      taskId: input.taskId,
      taskDisplayId: input.taskDisplayId,
      status: "running",
      blockedReason: null,
      taskBranchName: input.taskBranchName,
      model: input.model,
      reasoningLevel: input.reasoningLevel,
      baseBranch: input.baseBranch,
      headBefore: input.headBefore,
      headAfter: null,
      worktreeDirtyBefore: input.worktreeDirtyBefore,
      worktreeDirtyAfter: null,
      adapterRunId: null,
      rawLogKey: input.rawLogKey,
      startedAt: now,
      finishedAt: null,
      updatedAt: now,
    })
  })

  return { runId: input.runId, rawLogKey: input.rawLogKey }
}

async function finishRun(
  databasePath: string,
  runId: string,
  input: FinishRunInput
) {
  const now = new Date().toISOString()

  await withRunDb(databasePath, async (db) => {
    await db
      .update(runs)
      .set({
        status: input.status,
        blockedReason: input.blockedReason,
        headAfter: input.headAfter,
        worktreeDirtyAfter: input.worktreeDirtyAfter,
        adapterRunId: input.adapterRunId ?? null,
        finishedAt: now,
        updatedAt: now,
      })
      .where(eq(runs.id, runId))
  })
}

async function appendOperatorRunLog(
  paths: AppDataPaths,
  run: CreatedRun,
  type: string,
  payload: Record<string, unknown>
) {
  await appendRunLogEvent(paths, run.rawLogKey, {
    source: "operator",
    type,
    payload: {
      runId: run.runId,
      ...payload,
    },
  })
}

async function appendCursorRunLogEvent(
  paths: AppDataPaths,
  rawLogKey: string,
  event: unknown
) {
  await appendRunLogEvent(paths, rawLogKey, {
    source: "cursor",
    type: cursorEventType(event),
    payload: cursorEventPayload(event),
  })
}

function cursorEventType(event: unknown) {
  if (
    event &&
    typeof event === "object" &&
    "type" in event &&
    typeof event.type === "string"
  ) {
    return event.type
  }

  return "cursor.event"
}

function cursorEventPayload(event: unknown): Record<string, unknown> {
  if (event && typeof event === "object" && !Array.isArray(event)) {
    return event as Record<string, unknown>
  }

  return { event }
}

async function markInterruptedRuns(
  databasePath: string,
  interruptedBefore: string
) {
  const now = new Date().toISOString()

  return withRunDb(databasePath, async (db) => {
    const staleRuns = await db
      .select({ id: runs.id, taskId: runs.taskId })
      .from(runs)
      .where(
        and(eq(runs.status, "running"), lt(runs.startedAt, interruptedBefore))
      )

    for (const run of staleRuns) {
      await db
        .update(runs)
        .set({
          status: "blocked",
          blockedReason: "interrupted",
          finishedAt: now,
          updatedAt: now,
        })
        .where(eq(runs.id, run.id))

      const [task] = await db
        .select({
          id: taskRows.id,
          projectId: taskRows.projectId,
        })
        .from(taskRows)
        .where(
          and(eq(taskRows.id, run.taskId), eq(taskRows.status, "running"))
        )
        .limit(1)

      if (task) {
        const position = await nextRunPositionForStatus(
          db,
          task.projectId,
          "blocked"
        )
        await db
          .update(taskRows)
          .set({
            status: "blocked",
            position,
            blockedReason: "interrupted",
            updatedAt: now,
          })
          .where(
            and(eq(taskRows.id, run.taskId), eq(taskRows.status, "running"))
          )
      }
    }

    return staleRuns.length
  })
}

async function nextRunPositionForStatus(
  db: RunDb,
  projectId: string,
  status: TaskStatus
) {
  const [row] = await db
    .select({
      position: sql<number>`coalesce(max(${taskRows.position}), 0)`,
    })
    .from(taskRows)
    .where(
      and(
        eq(taskRows.projectId, projectId),
        eq(taskRows.status, status),
        isNull(taskRows.archivedAt)
      )
    )

  return (row?.position ?? 0) + 1
}

async function withRunDb<T>(
  databasePath: string,
  callback: (db: RunDb) => Promise<T>
) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { runs, tasks: taskRows } })

  try {
    return await callback(db)
  } finally {
    await client.close()
  }
}

export function createLocalGitRunAdapter(repoPath: string): GitRunAdapter {
  return {
    async repositoryExists() {
      return existsSync(repoPath)
    },

    async isGitRepository() {
      return git(repoPath, ["rev-parse", "--is-inside-work-tree"]).status === 0
    },

    async getCurrentBranch() {
      const result = git(repoPath, ["branch", "--show-current"])

      if (result.status !== 0) {
        return null
      }

      return result.stdout.trim() || null
    },

    async isWorktreeClean() {
      const result = git(repoPath, ["status", "--porcelain"])

      if (result.status !== 0) {
        throw new Error("git status failed")
      }

      return result.stdout.trim().length === 0
    },

    async getHeadSha() {
      const result = git(repoPath, ["rev-parse", "HEAD"])

      if (result.status !== 0) {
        throw new Error("git rev-parse HEAD failed")
      }

      return result.stdout.trim()
    },

    async checkoutOrCreateBranch(branchName: string, baseBranch: string) {
      const checkoutExisting = git(repoPath, ["checkout", branchName])

      if (checkoutExisting.status === 0) {
        return
      }

      const checkoutBase = git(repoPath, ["checkout", baseBranch])

      if (checkoutBase.status !== 0) {
        throw new Error("git checkout base branch failed")
      }

      const createBranch = git(repoPath, ["checkout", "-b", branchName])

      if (createBranch.status !== 0) {
        throw new Error("git checkout task branch failed")
      }
    },
  }
}

export function createCursorSdkRunAdapter(): CursorRunAdapter {
  return {
    async run(input) {
      return runCursorSdkAgent(input)
    },
  }
}

async function runCursorSdkAgent(input: {
  apiKey: string
  model: string
  prompt: string
  repoPath: string
  abortSignal: AbortSignal
  onEvent: (event: unknown) => Promise<void>
}) {
  const { Agent } = await importCursorSdk()
  const agent = await Agent.create({
    apiKey: input.apiKey,
    model: { id: input.model },
    local: { cwd: input.repoPath },
  })
  const run = await agent.send(input.prompt)
  const removeAbortListener = addAbortListener(input.abortSignal, () => {
    void run.cancel()
  })

  try {
    for await (const event of run.stream()) {
      await input.onEvent(event)
    }
  } finally {
    removeAbortListener()
  }

  return { adapterRunId: run.id != null ? String(run.id) : null }
}

export async function runCursorAdapterWithTimeout<T>(
  run: (abortSignal: AbortSignal) => Promise<T>,
  timeoutSeconds: number
): Promise<T> {
  const abortController = new AbortController()

  if (timeoutSeconds <= 0) {
    abortController.abort()
    throw new CursorRunTimeoutError("Run timed out")
  }

  let timeoutId: ReturnType<typeof setTimeout> | undefined

  try {
    return await Promise.race([
      run(abortController.signal),
      new Promise<T>((_, reject) => {
        timeoutId = setTimeout(() => {
          abortController.abort()
          reject(new CursorRunTimeoutError("Run timed out"))
        }, timeoutSeconds * 1000)
      }),
    ])
  } finally {
    if (timeoutId !== undefined) {
      clearTimeout(timeoutId)
    }
  }
}

function addAbortListener(signal: AbortSignal, listener: () => void) {
  if (signal.aborted) {
    listener()
    return () => {}
  }

  signal.addEventListener("abort", listener, { once: true })
  return () => signal.removeEventListener("abort", listener)
}

async function importCursorSdk(): Promise<CursorSdkModule> {
  const runtimeImport = new Function(
    "specifier",
    "return import(specifier)"
  ) as (specifier: string) => Promise<unknown>

  return (await runtimeImport("@cursor/sdk")) as CursorSdkModule
}

function git(repoPath: string, args: string[]) {
  return spawnSync("git", ["-C", repoPath, ...args], {
    encoding: "utf8",
  })
}
