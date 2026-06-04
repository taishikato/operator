import { spawnSync } from "node:child_process"

import type { Project } from "../projects/project-repository.ts"
import type { Task } from "./task-repository.ts"

export type TaskPrCommandAdapter = {
  run(input: { command: string; args: string[]; cwd: string }): Promise<{
    exitCode: number
    stdout: string
    stderr: string
  }>
}

export type TaskPullRequestDraft = {
  remote: string
  remoteUrl: string
  branchName: string
  baseBranch: string
  commitSha: string
  title: string
  body: string
  draft: true
}

export function canCreateTaskPullRequest(task: Task) {
  return (
    task.status === "review" &&
    task.taskBranchName !== null &&
    task.pullRequestUrl === null
  )
}

export function createLocalTaskPrCommandAdapter(): TaskPrCommandAdapter {
  return {
    async run(input) {
      const result = spawnSync(input.command, input.args, {
        cwd: input.cwd,
        encoding: "utf8",
      })

      return {
        exitCode: result.status ?? 1,
        stdout: result.stdout ?? "",
        stderr: result.stderr ?? (result.error ? result.error.message : ""),
      }
    },
  }
}

export async function prepareTaskPullRequestDraft(input: {
  command: TaskPrCommandAdapter
  project: Project
  task: Task
}): Promise<TaskPullRequestDraft> {
  const branchName = input.task.taskBranchName ?? ""
  const commitSha = (
    await runRequiredCommand(input.command, {
      command: "git",
      args: ["rev-parse", branchName],
      cwd: input.project.repoPath,
    })
  ).trim()
  const remoteUrl = (
    await runRequiredCommand(input.command, {
      command: "git",
      args: ["remote", "get-url", "origin"],
      cwd: input.project.repoPath,
    })
  ).trim()

  return {
    remote: "origin",
    remoteUrl,
    branchName,
    baseBranch: input.project.repositoryMetadata.defaultBranch ?? "main",
    commitSha,
    title: `${input.task.displayId}: ${input.task.title}`,
    body: buildPullRequestBody(input.task),
    draft: true,
  }
}

export async function createTaskPullRequest(input: {
  command: TaskPrCommandAdapter
  project: Project
  task: Task
  confirmation: {
    title: string
    body: string
    draft: true
  }
}) {
  const draft = await prepareTaskPullRequestDraft(input)
  await runRequiredCommand(input.command, {
    command: "git",
    args: ["push", "-u", draft.remote, draft.branchName],
    cwd: input.project.repoPath,
  })
  const pullRequestUrl = (
    await runRequiredCommand(input.command, {
      command: "gh",
      args: [
        "pr",
        "create",
        "--draft",
        "--base",
        draft.baseBranch,
        "--head",
        draft.branchName,
        "--title",
        input.confirmation.title,
        "--body",
        input.confirmation.body,
      ],
      cwd: input.project.repoPath,
    })
  ).trim()

  return { pullRequestUrl }
}

async function runRequiredCommand(
  command: TaskPrCommandAdapter,
  input: { command: string; args: string[]; cwd: string }
) {
  const result = await command.run(input)

  if (result.exitCode !== 0) {
    throw new Error(result.stderr.trim() || `${input.command} failed`)
  }

  return result.stdout
}

function buildPullRequestBody(task: Task) {
  return [
    "## Task",
    task.title,
    "",
    "## Body",
    task.bodyMarkdown.trim() || "(empty)",
    "",
    "## Acceptance criteria",
    task.acceptanceCriteriaMarkdown.trim() || "(empty)",
  ].join("\n")
}
