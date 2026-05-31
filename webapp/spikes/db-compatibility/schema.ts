import { text, sqliteTable } from "drizzle-orm/sqlite-core"

export const spikeProjects = sqliteTable("spike_projects", {
  // notNull() documents the intended non-null id invariant and makes Drizzle's TypeScript
  // insert/select types treat id as a required non-null string (app-layer enforcement).
  // NOTE: Drizzle Kit beta does NOT emit NOT NULL on a TEXT PRIMARY KEY, and SQLite/Turso
  // allow NULL in such a column, so the exported DDL Atlas applies has no DB-level NOT NULL
  // on id. The invariant therefore relies on the application always supplying an id.
  id: text("id").notNull().primaryKey(),
  key: text("key").notNull().unique(),
  name: text("name").notNull(),
  repoPath: text("repo_path").notNull().unique(),
})
