import { connect } from "@tursodatabase/database"
import { eq } from "drizzle-orm"
import { drizzle } from "drizzle-orm/tursodatabase/database"
import { stat } from "node:fs/promises"

import { exportSpikeProjectsSql } from "./export-spike-schema.ts"
import { spikeProjects } from "./schema.ts"

export type TursoDrizzleCompatibilitySpikeOptions = {
  databasePath: string
  /** DDL from `drizzle-kit export`; defaults to a fresh export at runtime. */
  createTableSql?: string
}

export async function runTursoDrizzleCompatibilitySpike({
  databasePath,
  createTableSql = exportSpikeProjectsSql(),
}: TursoDrizzleCompatibilitySpikeOptions) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { spikeProjects } })

  try {
    await client.exec(createTableSql)
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

export async function insertAndSelectSpikeProject(databasePath: string) {
  const client = await connect(databasePath)
  const db = drizzle({ client, schema: { spikeProjects } })

  try {
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

    return project
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
