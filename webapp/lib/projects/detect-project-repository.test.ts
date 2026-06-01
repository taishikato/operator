import assert from "node:assert/strict"
import { mkdir, mkdtemp, realpath, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"
import { promisify } from "node:util"
import { execFile } from "node:child_process"

import { detectProjectRepository } from "./detect-project-repository.ts"

const execFileAsync = promisify(execFile)

test("detectProjectRepository returns basic metadata for a valid Git repository", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-repo-"))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await writeFile(join(repoPath, "package.json"), "{}\n")
  await execFileAsync("git", ["add", "package.json"], { cwd: repoPath })
  await execFileAsync("git", ["commit", "-m", "Initial commit"], {
    cwd: repoPath,
    env: {
      ...process.env,
      GIT_AUTHOR_NAME: "Operator Test",
      GIT_AUTHOR_EMAIL: "operator@example.com",
      GIT_COMMITTER_NAME: "Operator Test",
      GIT_COMMITTER_EMAIL: "operator@example.com",
    },
  })

  const repositoryRoot = await realpath(repoPath)
  const metadata = await detectProjectRepository(repoPath)

  assert.deepEqual(metadata, {
    path: repositoryRoot,
    name: repositoryRoot.split("/").at(-1),
    defaultBranch: "main",
    remoteUrl: null,
    githubSlug: null,
    packageManagers: ["npm"],
    instructionFiles: [],
  })
})

test("detectProjectRepository rejects a path that is not a Git repository", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-non-repo-"))

  await assert.rejects(() => detectProjectRepository(repoPath), {
    name: "ProjectRepositoryDetectionError",
    code: "not_git_repository",
    message: "Path is not a Git repository",
  })
})

test("detectProjectRepository returns a GitHub slug for an origin remote", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-github-repo-"))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await execFileAsync(
    "git",
    ["remote", "add", "origin", "git@github.com:example/operator.git"],
    { cwd: repoPath }
  )

  const metadata = await detectProjectRepository(repoPath)

  assert.equal(metadata.remoteUrl, "git@github.com:example/operator.git")
  assert.equal(metadata.githubSlug, "example/operator")
})

test("detectProjectRepository returns a GitHub slug for an HTTPS origin remote", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-github-https-repo-"))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await execFileAsync(
    "git",
    ["remote", "add", "origin", "https://github.com/example/operator.git"],
    { cwd: repoPath }
  )

  const metadata = await detectProjectRepository(repoPath)

  assert.equal(metadata.remoteUrl, "https://github.com/example/operator.git")
  assert.equal(metadata.githubSlug, "example/operator")
})

test("detectProjectRepository returns a GitHub slug for an SSH URL origin remote", async () => {
  const repoPath = await mkdtemp(
    join(tmpdir(), "operator-github-ssh-url-repo-")
  )

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await execFileAsync(
    "git",
    ["remote", "add", "origin", "ssh://git@github.com/example/operator.git"],
    { cwd: repoPath }
  )

  const metadata = await detectProjectRepository(repoPath)

  assert.equal(metadata.remoteUrl, "ssh://git@github.com/example/operator.git")
  assert.equal(metadata.githubSlug, "example/operator")
})

test("detectProjectRepository returns present instruction files", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-instructions-repo-"))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await writeFile(join(repoPath, "AGENTS.md"), "Repository instructions\n")
  await writeFile(join(repoPath, "CLAUDE.md"), "Claude instructions\n")
  await mkdir(join(repoPath, ".cursor", "rules"), { recursive: true })
  await writeFile(
    join(repoPath, ".cursor", "rules", "operator.mdc"),
    "Cursor instructions\n"
  )

  const metadata = await detectProjectRepository(repoPath)

  assert.deepEqual(metadata.instructionFiles, [
    "AGENTS.md",
    "CLAUDE.md",
    ".cursor/rules",
  ])
})

test("detectProjectRepository returns deterministic package manager hints", async () => {
  const repoPath = await mkdtemp(join(tmpdir(), "operator-package-repo-"))

  await execFileAsync("git", ["init", "-b", "main"], { cwd: repoPath })
  await writeFile(join(repoPath, "package.json"), "{}\n")
  await writeFile(join(repoPath, "package-lock.json"), "{}\n")
  await writeFile(join(repoPath, "pnpm-lock.yaml"), "lockfileVersion: '9.0'\n")
  await writeFile(join(repoPath, "yarn.lock"), "\n")
  await writeFile(join(repoPath, "bun.lockb"), "\n")

  const metadata = await detectProjectRepository(repoPath)

  assert.deepEqual(metadata.packageManagers, ["pnpm", "yarn", "bun", "npm"])
})
