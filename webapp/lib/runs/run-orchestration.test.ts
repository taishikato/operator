import { connect } from "@tursodatabase/database"
import { eq } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { exportOperatorSchemaSql } from "../db/schema-export.ts"
import { runs } from "../db/schema.ts"
import {
  createProjectRepository,
  type CreateProjectInput,
} from "../projects/project-repository.ts"
import { createTaskRepository } from "../tasks/task-repository.ts"
import {
  buildCursorRunPrompt,
  canRunTaskNow,
  classifyRunResult,
  createRunOrchestrator,
  reconcileStaleRunsOnStartup,
  resetStaleRunReconciliationForTests,
  type CursorRunAdapter,
  type GitRunAdapter,
} from "./run-orchestration.ts"

test("canRunTaskNow exposes Run Now only for non-terminal non-Running Task statuses", () => {
  assert.deepEqual(
    ["backlog", "ready", "blocked", "review"].filter((status) =>
      canRunTaskNow(status)
    ),
    ["backlog", "ready", "blocked", "review"]
  )
  assert.equal(canRunTaskNow("running"), false)
  assert.equal(canRunTaskNow("done"), false)
})

test("buildCursorRunPrompt includes Task context, constraints, checks, English commits, and no-push instruction", () => {
  const prompt = buildCursorRunPrompt({
    projectKey: "OP",
    projectName: "Operator",
    repoPath: "/Users/example/operator",
    branchName: "operator/op-10-cursor-sdk-run-orchestration-tracer",
    task: {
      displayId: "OP-10",
      title: "Cursor SDK run orchestration tracer",
      bodyMarkdown: "Build the first end-to-end Run Now path.",
      acceptanceCriteriaMarkdown:
        "- Classifies HEAD delta\n- Reuses stored Task branch",
    },
    checks: ["pnpm test", "pnpm typecheck", "pnpm lint", "pnpm build"],
  })

  assert.match(prompt, /OP-10/)
  assert.match(prompt, /Cursor SDK run orchestration tracer/)
  assert.match(prompt, /Build the first end-to-end Run Now path/)
  assert.match(prompt, /Classifies HEAD delta/)
  assert.match(prompt, /operator\/op-10-cursor-sdk-run-orchestration-tracer/)
  assert.match(prompt, /current branch must remain/)
  assert.match(prompt, /pnpm test/)
  assert.match(prompt, /pnpm build/)
  assert.match(prompt, /Commit message must be in English/)
  assert.match(prompt, /Do not push/)
})

test("runTaskNow rejects a non-runnable Task before persisting a branch", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const tasks = createTaskRepository({ databasePath })
  await tasks.moveTaskToStatus(task.id, "done")
  const cursor = new FakeCursorRunAdapter()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter(),
    cursorAdapter: cursor,
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "task_not_runnable")
  assert.equal(result.taskBranchName, "")
  assert.equal(result.runId, null)
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "done")
  assert.equal(saved?.blockedReason, null)
  assert.equal(saved?.taskBranchName, null)
})

test("runTaskNow blocks a dirty working tree before launching the Cursor adapter", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const git = new FakeGitRunAdapter({
    cleanBefore: false,
    headBefore: "head-before",
  })
  const cursor = new FakeCursorRunAdapter()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: git,
    cursorAdapter: cursor,
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await createTaskRepository({
    databasePath,
  }).getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "dirty_worktree")
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "dirty_worktree")
})

test("runTaskNow generates a Task branch once and reuses it after title changes", async () => {
  const { databasePath, task } = await createRunnableTaskForTest({
    title: "Ship Run Now!",
  })
  const tasks = createTaskRepository({ databasePath })
  const git = new FakeGitRunAdapter({
    cleanBefore: true,
    cleanAfter: true,
    headBefore: "a",
    headAfter: "b",
  })
  const cursor = new FakeCursorRunAdapter()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: git,
    cursorAdapter: cursor,
  })

  const firstRun = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  await tasks.updateTaskInstructions(task.id, {
    title: "Renamed after first run",
    bodyMarkdown: task.bodyMarkdown,
    acceptanceCriteriaMarkdown: task.acceptanceCriteriaMarkdown,
    modelOverride: null,
    reasoningLevelOverride: null,
  })
  git.setPostRunObservation({ cleanAfter: true, headAfter: "c" })
  const secondRun = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)

  assert.equal(firstRun.taskBranchName, "operator/op-1-ship-run-now")
  assert.equal(secondRun.taskBranchName, "operator/op-1-ship-run-now")
  assert.equal(saved?.taskBranchName, "operator/op-1-ship-run-now")
  assert.deepEqual(git.checkedOutBranches, [
    "operator/op-1-ship-run-now",
    "operator/op-1-ship-run-now",
  ])
  assert.equal(cursor.calls.length, 2)
})

test("runTaskNow classifies HEAD delta and worktree state after the Cursor adapter returns", async () => {
  const cases = [
    {
      name: "commit delta with clean worktree",
      headBefore: "a",
      headAfter: "b",
      cleanAfter: true,
      expectedStatus: "review",
      expectedBlockedReason: null,
    },
    {
      name: "no commit with dirty worktree",
      headBefore: "a",
      headAfter: "a",
      cleanAfter: false,
      expectedStatus: "blocked",
      expectedBlockedReason: "worktree_dirty_no_commit",
    },
    {
      name: "no commit with clean worktree",
      headBefore: "a",
      headAfter: "a",
      cleanAfter: true,
      expectedStatus: "blocked",
      expectedBlockedReason: "no_commit_created",
    },
    {
      name: "commit delta with dirty worktree",
      headBefore: "a",
      headAfter: "b",
      cleanAfter: false,
      expectedStatus: "blocked",
      expectedBlockedReason: "dirty_after_commit",
    },
  ] as const

  for (const item of cases) {
    assert.deepEqual(
      classifyRunResult({
        headBefore: item.headBefore,
        headAfter: item.headAfter,
        cleanAfter: item.cleanAfter,
      }),
      {
        status: item.expectedStatus,
        blockedReason: item.expectedBlockedReason,
      },
      item.name
    )

    const { databasePath, task } = await createRunnableTaskForTest()
    const orchestrator = createRunOrchestrator({
      databasePath,
      cursorApiKey: "test-cursor-key",
      gitAdapter: new FakeGitRunAdapter({
        cleanBefore: true,
        cleanAfter: item.cleanAfter,
        headBefore: item.headBefore,
        headAfter: item.headAfter,
      }),
      cursorAdapter: new FakeCursorRunAdapter(),
    })

    const result = await orchestrator.runTaskNow({
      projectKey: "OP",
      taskDisplayId: task.displayId,
    })

    assert.equal(result.status, item.expectedStatus, item.name)
    assert.equal(result.blockedReason, item.expectedBlockedReason, item.name)
  }
})

test("runTaskNow rejects when the Task is no longer runnable at claim time", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const tasks = createTaskRepository({ databasePath })
  const cursor = new FakeCursorRunAdapter()

  assert.equal(await tasks.tryClaimTaskForRun(task.id), true)

  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter({
      cleanBefore: true,
      cleanAfter: true,
      headBefore: "a",
      headAfter: "b",
    }),
    cursorAdapter: cursor,
  })
  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "task_not_runnable")
  assert.equal(result.runId, null)
  assert.equal(cursor.calls.length, 0)
  assert.equal(await countRunsForTask(databasePath, task.id), 0)
})

test("runTaskNow records post-run git observation failures as git_error", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FailingPostRunHeadGitRunAdapter(),
    cursorAdapter: new FakeCursorRunAdapter(),
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await createTaskRepository({
    databasePath,
  }).getActiveTaskByDisplayId(task.displayId)
  const run = await selectRunForTest(databasePath, result.runId!)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "git_error")
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "git_error")
  assert.equal(run.status, "blocked")
  assert.equal(run.blocked_reason, "git_error")
  assert.equal(run.head_after, null)
})

test("reconcileInterruptedRuns marks stale Running Tasks and Runs as interrupted", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const tasks = createTaskRepository({ databasePath })
  await tasks.setTaskBranchName(task.id, "operator/op-1-stale-run")
  await tasks.moveTaskToStatus(task.id, "running")
  const runId = await insertRunningRunForTest({
    databasePath,
    taskId: task.id,
    taskDisplayId: task.displayId,
    startedAt: "2026-06-01T00:00:00.000Z",
  })
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter(),
    cursorAdapter: new FakeCursorRunAdapter(),
  })

  const result = await orchestrator.reconcileInterruptedRuns({
    interruptedBefore: new Date("2026-06-02T00:00:00.000Z"),
  })
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)
  const run = await selectRunForTest(databasePath, runId)

  assert.equal(result.interruptedRuns, 1)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "interrupted")
  assert.equal(run.status, "blocked")
  assert.equal(run.blocked_reason, "interrupted")
})

test("reconcileInterruptedRuns leaves Tasks that already left Running unchanged", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const tasks = createTaskRepository({ databasePath })
  await tasks.moveTaskToStatus(task.id, "review")
  const runId = await insertRunningRunForTest({
    databasePath,
    taskId: task.id,
    taskDisplayId: task.displayId,
    startedAt: "2026-06-01T00:00:00.000Z",
  })
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter(),
    cursorAdapter: new FakeCursorRunAdapter(),
  })

  await orchestrator.reconcileInterruptedRuns({
    interruptedBefore: new Date("2026-06-02T00:00:00.000Z"),
  })
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)
  const run = await selectRunForTest(databasePath, runId)

  assert.equal(saved?.status, "review")
  assert.equal(saved?.blockedReason, null)
  assert.equal(run.status, "blocked")
  assert.equal(run.blocked_reason, "interrupted")
})

test("reconcileStaleRunsOnStartup marks in-flight runs as interrupted", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const tasks = createTaskRepository({ databasePath })
  await tasks.setTaskBranchName(task.id, "operator/op-1-stale-run")
  await tasks.moveTaskToStatus(task.id, "running")
  await insertRunningRunForTest({
    databasePath,
    taskId: task.id,
    taskDisplayId: task.displayId,
    startedAt: new Date(Date.now() - 60_000).toISOString(),
  })

  resetStaleRunReconciliationForTests()
  const result = await reconcileStaleRunsOnStartup(databasePath)
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.interruptedRuns, 1)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "interrupted")
})

test("runTaskNow records adapter failures as agent_error instead of escaping the orchestration boundary", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter(),
    cursorAdapter: {
      async run() {
        throw new Error("fake Cursor failure")
      },
    },
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await createTaskRepository({
    databasePath,
  }).getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "agent_error")
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "agent_error")
})

test("runTaskNow records preflight git status failures as git_error without launching Cursor", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const cursor = new FakeCursorRunAdapter()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new ThrowingWorktreeGitRunAdapter(),
    cursorAdapter: cursor,
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await createTaskRepository({
    databasePath,
  }).getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "git_error")
  assert.equal(result.runId, null)
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "git_error")
})

test("runTaskNow records Cursor adapter timeouts as timeout and finishes the run", async () => {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  await projects.createProject(
    createProjectInput({ defaults: { model: "cursor/gpt-5", reasoningLevel: "high", runTimeoutSeconds: 1 } })
  )
  const tasks = createTaskRepository({ databasePath })
  const task = await tasks.createTask({
    projectId: (await projects.getActiveProjectByKey("OP"))!.id,
    title: "Run Task now",
    bodyMarkdown: "Run the Task through Cursor.",
    acceptanceCriteriaMarkdown: "- It finishes with a classified outcome",
  })
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FakeGitRunAdapter({
      cleanBefore: true,
      cleanAfter: true,
      headBefore: "a",
      headAfter: "a",
    }),
    cursorAdapter: new HangingCursorRunAdapter(),
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await tasks.getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "timeout")
  assert.ok(result.runId)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "timeout")
})

test("runTaskNow records branch checkout failures as git_error without launching Cursor", async () => {
  const { databasePath, task } = await createRunnableTaskForTest()
  const cursor = new FakeCursorRunAdapter()
  const orchestrator = createRunOrchestrator({
    databasePath,
    cursorApiKey: "test-cursor-key",
    gitAdapter: new FailingCheckoutGitRunAdapter(),
    cursorAdapter: cursor,
  })

  const result = await orchestrator.runTaskNow({
    projectKey: "OP",
    taskDisplayId: task.displayId,
  })
  const saved = await createTaskRepository({
    databasePath,
  }).getActiveTaskByDisplayId(task.displayId)

  assert.equal(result.status, "blocked")
  assert.equal(result.blockedReason, "git_error")
  assert.equal(cursor.calls.length, 0)
  assert.equal(saved?.status, "blocked")
  assert.equal(saved?.blockedReason, "git_error")
})

async function createRunnableTaskForTest(
  overrides: Partial<{
    title: string
    status: "backlog" | "ready" | "blocked" | "review"
  }> = {}
) {
  const databasePath = await createDatabaseForTest()
  const projects = createProjectRepository({ databasePath })
  const project = await projects.createProject(createProjectInput())
  const tasks = createTaskRepository({ databasePath })
  const task = await tasks.createTask({
    projectId: project.id,
    title: overrides.title ?? "Run Task now",
    bodyMarkdown: "Run the Task through Cursor.",
    acceptanceCriteriaMarkdown: "- It finishes with a classified outcome",
  })

  if (overrides.status) {
    await tasks.moveTaskToStatus(task.id, overrides.status)
  }

  return { databasePath, project, task }
}

async function createDatabaseForTest() {
  const directory = await mkdtemp(join(tmpdir(), "operator-runs-"))
  const databasePath = join(directory, "operator.db")
  const client = await connect(databasePath)

  try {
    await client.exec(exportOperatorSchemaSql())
  } finally {
    await client.close()
  }

  return databasePath
}

async function insertRunningRunForTest({
  databasePath,
  taskId,
  taskDisplayId,
  startedAt,
}: {
  databasePath: string
  taskId: string
  taskDisplayId: string
  startedAt: string
}) {
  const client = await connect(databasePath)

  try {
    const db = drizzle({ client, schema: { runs } })
    await db.insert(runs).values({
      id: "run_stale",
      projectId: "project_id",
      taskId,
      taskDisplayId,
      status: "running",
      blockedReason: null,
      taskBranchName: "operator/op-1-stale-run",
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      baseBranch: "main",
      headBefore: "a",
      headAfter: null,
      worktreeDirtyBefore: false,
      worktreeDirtyAfter: null,
      adapterRunId: null,
      startedAt,
      finishedAt: null,
      updatedAt: startedAt,
    })
  } finally {
    await client.close()
  }

  return "run_stale"
}

async function selectRunForTest(databasePath: string, runId: string) {
  const client = await connect(databasePath)

  try {
    const db = drizzle({ client, schema: { runs } })
    const [run] = await db
      .select({
        status: runs.status,
        blocked_reason: runs.blockedReason,
        head_after: runs.headAfter,
      })
      .from(runs)
      .where(eq(runs.id, runId))

    return run as {
      status: string
      blocked_reason: string | null
      head_after: string | null
    }
  } finally {
    await client.close()
  }
}

async function countRunsForTask(databasePath: string, taskId: string) {
  const client = await connect(databasePath)

  try {
    const db = drizzle({ client, schema: { runs } })
    const rows = await db
      .select({ id: runs.id })
      .from(runs)
      .where(eq(runs.taskId, taskId))

    return rows.length
  } finally {
    await client.close()
  }
}

function createProjectInput(
  overrides: Partial<CreateProjectInput> = {}
): CreateProjectInput {
  return {
    key: "OP",
    displayName: "Operator",
    repoPath: "/Users/example/operator",
    repositoryMetadata: {
      name: "operator",
      defaultBranch: "main",
      remoteUrl: "git@github.com:example/operator.git",
      githubSlug: "example/operator",
      packageManagers: ["pnpm"],
      instructionFiles: ["AGENTS.md"],
    },
    defaults: {
      model: "cursor/gpt-5",
      reasoningLevel: "high",
      runTimeoutSeconds: 3600,
    },
    schedule: {
      enabled: false,
      dailyTime: "09:00",
      timezone: "Asia/Tokyo",
      scheduledRunLimit: 1,
    },
    ...overrides,
  }
}

class FakeGitRunAdapter implements GitRunAdapter {
  checkedOutBranches: string[] = []
  private cleanBefore: boolean
  private cleanAfter: boolean
  private headBefore: string
  private headAfter: string
  private headCalls = 0

  constructor(
    options: Partial<{
      cleanBefore: boolean
      cleanAfter: boolean
      headBefore: string
      headAfter: string
    }> = {}
  ) {
    this.cleanBefore = options.cleanBefore ?? true
    this.cleanAfter = options.cleanAfter ?? true
    this.headBefore = options.headBefore ?? "head-before"
    this.headAfter = options.headAfter ?? "head-after"
  }

  async repositoryExists() {
    return true
  }

  async isGitRepository() {
    return true
  }

  async getCurrentBranch() {
    return "main"
  }

  async isWorktreeClean() {
    return this.checkedOutBranches.length === 0
      ? this.cleanBefore
      : this.cleanAfter
  }

  async getHeadSha() {
    this.headCalls += 1
    return this.headCalls % 2 === 1 ? this.headBefore : this.headAfter
  }

  async checkoutOrCreateBranch(branchName: string) {
    this.checkedOutBranches.push(branchName)
  }

  setPostRunObservation({
    cleanAfter,
    headAfter,
  }: {
    cleanAfter: boolean
    headAfter: string
  }) {
    this.cleanAfter = cleanAfter
    this.headAfter = headAfter
  }
}

class FakeCursorRunAdapter implements CursorRunAdapter {
  calls: Array<{ prompt: string; branchName: string; model: string }> = []

  async run(input: { prompt: string; branchName: string; model: string }) {
    this.calls.push(input)
    return { adapterRunId: `fake-${this.calls.length}` }
  }
}

class FailingCheckoutGitRunAdapter extends FakeGitRunAdapter {
  async checkoutOrCreateBranch() {
    throw new Error("fake checkout failure")
  }
}

class ThrowingWorktreeGitRunAdapter extends FakeGitRunAdapter {
  override async isWorktreeClean(): Promise<boolean> {
    throw new Error("git status failed")
  }
}

class FailingPostRunHeadGitRunAdapter extends FakeGitRunAdapter {
  private headShaCalls = 0

  override async getHeadSha(): Promise<string> {
    this.headShaCalls += 1

    if (this.headShaCalls === 2) {
      throw new Error("post-run head failed")
    }

    return this.headShaCalls === 1 ? "a" : "b"
  }
}

class HangingCursorRunAdapter implements CursorRunAdapter {
  async run(
    input: Parameters<CursorRunAdapter["run"]>[0]
  ): Promise<{ adapterRunId?: string | null }> {
    void input
    return new Promise(() => {})
  }
}
