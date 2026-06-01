import { execFile } from "node:child_process"
import { access } from "node:fs/promises"
import { basename, join } from "node:path"
import { promisify } from "node:util"

const execFileAsync = promisify(execFile)

export type ProjectRepositoryMetadata = {
  path: string
  name: string
  defaultBranch: string | null
  remoteUrl: string | null
  githubSlug: string | null
  packageManagers: string[]
  instructionFiles: string[]
}

export class ProjectRepositoryDetectionError extends Error {
  code: "not_git_repository"

  constructor(code: "not_git_repository", message: string) {
    super(message)
    this.name = "ProjectRepositoryDetectionError"
    this.code = code
  }
}

export async function detectProjectRepository(
  repoPath: string
): Promise<ProjectRepositoryMetadata> {
  const path = await readRepositoryRoot(repoPath)
  const defaultBranch = await readDefaultBranch(path)
  const remoteUrl = await readOriginRemoteUrl(path)

  return {
    path,
    name: basename(path),
    defaultBranch,
    remoteUrl,
    githubSlug: remoteUrl ? parseGitHubSlug(remoteUrl) : null,
    packageManagers: await detectPackageManagers(path),
    instructionFiles: await detectInstructionFiles(path),
  }
}

async function readRepositoryRoot(repoPath: string) {
  try {
    return await git(repoPath, ["rev-parse", "--show-toplevel"])
  } catch {
    throw new ProjectRepositoryDetectionError(
      "not_git_repository",
      "Path is not a Git repository"
    )
  }
}

async function readDefaultBranch(repoPath: string) {
  const originHead = await maybeGit(repoPath, [
    "symbolic-ref",
    "--short",
    "refs/remotes/origin/HEAD",
  ])

  if (originHead) {
    return originHead.replace(/^origin\//, "")
  }

  return maybeGit(repoPath, ["branch", "--show-current"])
}

async function readOriginRemoteUrl(repoPath: string) {
  return maybeGit(repoPath, ["remote", "get-url", "origin"])
}

async function detectPackageManagers(repoPath: string) {
  const hints = [
    ["pnpm", "pnpm-lock.yaml"],
    ["yarn", "yarn.lock"],
    ["bun", "bun.lock"],
    ["bun", "bun.lockb"],
    ["npm", "package-lock.json"],
    ["npm", "package.json"],
  ] as const

  const detected = new Set<string>()

  for (const [packageManager, fileName] of hints) {
    try {
      await access(join(repoPath, fileName))
      detected.add(packageManager)
    } catch {
      // Missing hint files are expected for repositories that are not JavaScript projects.
    }
  }

  return [...detected]
}

async function detectInstructionFiles(repoPath: string) {
  const hints = ["AGENTS.md", "CLAUDE.md", ".cursor/rules"] as const
  const detected: string[] = []

  for (const fileName of hints) {
    try {
      await access(join(repoPath, fileName))
      detected.push(fileName)
    } catch {
      // Missing instruction files are expected for repositories without agent-specific guidance.
    }
  }

  return detected
}

function parseGitHubSlug(remoteUrl: string) {
  const match = remoteUrl.match(
    /^(?:git@github\.com:|https:\/\/github\.com\/|ssh:\/\/git@github\.com\/)([^/]+\/[^/]+?)(?:\.git)?$/
  )

  return match?.[1] ?? null
}

async function maybeGit(repoPath: string, args: string[]) {
  try {
    const output = await git(repoPath, args)

    return output || null
  } catch {
    return null
  }
}

async function git(repoPath: string, args: string[]) {
  const { stdout } = await execFileAsync("git", args, { cwd: repoPath })

  return stdout.trim()
}
