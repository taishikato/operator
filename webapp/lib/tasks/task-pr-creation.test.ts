import assert from "node:assert/strict"
import { test } from "node:test"

import {
  createTaskPullRequest,
  prepareTaskPullRequestDraft,
  type TaskPrCommandAdapter,
} from "./task-pr-creation.ts"
import type { Project } from "../projects/project-repository.ts"
import type { Task } from "./task-repository.ts"

test("prepareTaskPullRequestDraft previews branch, remote, commit, title, body, and draft status without pushing", async () => {
  const command = new FakeTaskPrCommandAdapter({
    "git rev-parse HEAD": "abc123\n",
    "git remote get-url origin": "git@github.com:example/operator.git\n",
  })

  const draft = await prepareTaskPullRequestDraft({
    command,
    project: project(),
    task: task({
      status: "review",
      taskBranchName: "operator/op-14-manual-pr",
    }),
  })

  assert.deepEqual(draft, {
    remote: "origin",
    remoteUrl: "git@github.com:example/operator.git",
    branchName: "operator/op-14-manual-pr",
    baseBranch: "main",
    commitSha: "abc123",
    title: "OP-14: Manual draft PR creation",
    body: [
      "## Task",
      "Manual draft PR creation",
      "",
      "## Body",
      "Create a draft PR from a Review Task.",
      "",
      "## Acceptance criteria",
      "- Shows confirmation",
    ].join("\n"),
    draft: true,
  })
  assert.deepEqual(
    command.calls.map((call) => `${call.command} ${call.args.join(" ")}`),
    ["git rev-parse HEAD", "git remote get-url origin"]
  )
})

test("createTaskPullRequest pushes the confirmed branch before creating a draft PR with gh", async () => {
  const command = new FakeTaskPrCommandAdapter({
    "git rev-parse HEAD": "abc123\n",
    "git remote get-url origin": "git@github.com:example/operator.git\n",
    "git push -u origin operator/op-14-manual-pr": "",
    "gh pr create --draft --base main --head operator/op-14-manual-pr --title OP-14: Manual draft PR creation --body Confirmed body":
      "https://github.com/example/operator/pull/14\n",
  })

  const result = await createTaskPullRequest({
    command,
    project: project(),
    task: task({
      status: "review",
      taskBranchName: "operator/op-14-manual-pr",
    }),
    confirmation: {
      title: "OP-14: Manual draft PR creation",
      body: "Confirmed body",
      draft: true,
    },
  })

  assert.deepEqual(result, {
    pullRequestUrl: "https://github.com/example/operator/pull/14",
  })
  assert.deepEqual(
    command.calls.map((call) => `${call.command} ${call.args.join(" ")}`),
    [
      "git rev-parse HEAD",
      "git remote get-url origin",
      "git push -u origin operator/op-14-manual-pr",
      "gh pr create --draft --base main --head operator/op-14-manual-pr --title OP-14: Manual draft PR creation --body Confirmed body",
    ]
  )
})

class FakeTaskPrCommandAdapter implements TaskPrCommandAdapter {
  calls: Array<{ command: string; args: string[]; cwd: string }> = []
  private readonly outputs: Record<string, string>

  constructor(outputs: Record<string, string>) {
    this.outputs = outputs
  }

  async run(input: { command: string; args: string[]; cwd: string }) {
    this.calls.push(input)
    const key = `${input.command} ${input.args.join(" ")}`
    const stdout = this.outputs[key]

    if (stdout === undefined) {
      return {
        exitCode: 1,
        stdout: "",
        stderr: `Unexpected command: ${key}`,
      }
    }

    return { exitCode: 0, stdout, stderr: "" }
  }
}

function project(overrides: Partial<Project> = {}): Project {
  return {
    id: "project_1",
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
      lastScheduledLocalDate: null,
    },
    nextTaskNumber: 15,
    createdAt: "2026-06-01T00:00:00.000Z",
    updatedAt: "2026-06-01T00:00:00.000Z",
    removedAt: null,
    ...overrides,
  }
}

function task(overrides: Partial<Task> = {}): Task {
  return {
    id: "task_14",
    projectId: "project_1",
    number: 14,
    displayId: "OP-14",
    title: "Manual draft PR creation",
    bodyMarkdown: "Create a draft PR from a Review Task.",
    acceptanceCriteriaMarkdown: "- Shows confirmation",
    status: "backlog",
    position: 1,
    taskBranchName: null,
    pullRequestUrl: null,
    pullRequestError: null,
    blockedReason: null,
    modelOverride: null,
    reasoningLevelOverride: null,
    createdAt: "2026-06-01T00:00:00.000Z",
    updatedAt: "2026-06-01T00:00:00.000Z",
    archivedAt: null,
    ...overrides,
  }
}
