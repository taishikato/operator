import { spawnSync } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

import { spawnFailureDetail } from "./spawn-output.ts"

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
