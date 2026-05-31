import assert from "node:assert/strict"
import { mkdtemp } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import { runTursoDrizzleCompatibilitySpike } from "./turso-drizzle-spike.ts"

test("Turso local storage can create and query a Drizzle-defined Project-like table", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-db-spike-"))
  const result = await runTursoDrizzleCompatibilitySpike({
    databasePath: join(directory, "operator.db"),
  })

  assert.deepEqual(result, {
    databaseCreated: true,
    project: {
      id: "project_01",
      key: "OP",
      name: "Operator",
      repoPath: "/tmp/operator",
    },
  })
})
