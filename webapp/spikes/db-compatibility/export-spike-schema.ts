import { spawnSync } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const webappRoot = join(
  dirname(fileURLToPath(import.meta.url)),
  "../..",
)

export const spikeSchemaRelativePath = "./spikes/db-compatibility/schema.ts"

export function exportSpikeProjectsSql() {
  const result = spawnSync(
    "pnpm",
    [
      "exec",
      "drizzle-kit",
      "export",
      "--dialect",
      "sqlite",
      "--schema",
      spikeSchemaRelativePath,
    ],
    {
      cwd: webappRoot,
      encoding: "utf8",
    },
  )

  if (result.status !== 0) {
    const detail = result.stderr.trim() || result.stdout.trim() || "unknown error"
    throw new Error(`drizzle-kit export failed: ${detail}`)
  }

  return result.stdout.trim()
}
