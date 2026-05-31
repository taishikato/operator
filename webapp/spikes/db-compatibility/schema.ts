import { text, sqliteTable } from "drizzle-orm/sqlite-core"

export const spikeProjects = sqliteTable("spike_projects", {
  id: text("id").primaryKey(),
  key: text("key").notNull().unique(),
  name: text("name").notNull(),
  repoPath: text("repo_path").notNull().unique(),
})
