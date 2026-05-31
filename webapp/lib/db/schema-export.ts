import { spawnSync } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const webappRoot = join(dirname(fileURLToPath(import.meta.url)), "../..")

export const operatorSchemaRelativePath = "./lib/db/schema.ts"

export function exportOperatorSchemaSql() {
  const result = spawnSync(
    "pnpm",
    [
      "exec",
      "drizzle-kit",
      "export",
      "--dialect",
      "sqlite",
      "--schema",
      operatorSchemaRelativePath,
    ],
    {
      cwd: webappRoot,
      encoding: "utf8",
    }
  )

  if (result.status !== 0) {
    const detail = spawnFailureDetail(result)
    throw new Error(`drizzle-kit export failed: ${detail}`)
  }

  return result.stdout.trim()
}

function spawnFailureDetail(result: ReturnType<typeof spawnSync>) {
  return (
    result.error?.message ??
    spawnOutputText(result.stderr) ??
    spawnOutputText(result.stdout) ??
    "unknown error"
  )
}

function spawnOutputText(output: ReturnType<typeof spawnSync>["stderr"]) {
  const text = String(output ?? "").trim()
  return text || undefined
}
