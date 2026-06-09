import type { spawnSync } from "node:child_process"

export function spawnFailureDetail(result: ReturnType<typeof spawnSync>) {
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
