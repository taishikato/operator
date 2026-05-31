import { connect } from "@tursodatabase/database"
import { eq } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { stat } from "node:fs/promises"

import { spikeProjects } from "./schema.ts"

// Constraints kept in sync with `drizzle-kit export` output for schema.ts (the source of
// truth Atlas applies). Crucially, `id` has no NOT NULL here because Drizzle Kit beta does
// not emit it for a TEXT PRIMARY KEY; matching that exactly keeps the spike honest about the
// schema the real workflow produces rather than testing a stronger, fictional constraint.
const createSpikeProjectsSql = `
CREATE TABLE IF NOT EXISTS spike_projects (
  id TEXT PRIMARY KEY,
  key TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  repo_path TEXT NOT NULL UNIQUE
);
`

export type TursoDrizzleCompatibilitySpikeOptions = {
  databasePath: string
}

export async function runTursoDrizzleCompatibilitySpike({
  databasePath,
}: TursoDrizzleCompatibilitySpikeOptions) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { spikeProjects } })

  try {
    await client.exec(createSpikeProjectsSql)
    await db.insert(spikeProjects).values({
      id: "project_01",
      key: "OP",
      name: "Operator",
      repoPath: "/tmp/operator",
    })

    const [project] = await db
      .select()
      .from(spikeProjects)
      .where(eq(spikeProjects.id, "project_01"))
      .limit(1)

    return {
      databaseCreated: await fileExists(databasePath),
      project,
    }
  } finally {
    await client.close()
  }
}

async function fileExists(path: string) {
  try {
    await stat(path)
    return true
  } catch {
    return false
  }
}
