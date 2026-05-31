import { sql } from "drizzle-orm"
import {
  integer,
  text,
  sqliteTable,
  uniqueIndex,
} from "drizzle-orm/sqlite-core"

export const operatorMetadata = sqliteTable("operator_metadata", {
  key: text("key").notNull().primaryKey(),
  value: text("value").notNull(),
  updatedAt: text("updated_at").notNull(),
})

export const projects = sqliteTable(
  "projects",
  {
    id: text("id").notNull().primaryKey(),
    key: text("key").notNull(),
    displayName: text("display_name").notNull(),
    repoPath: text("repo_path").notNull(),
    repositoryName: text("repository_name").notNull(),
    repositoryDefaultBranch: text("repository_default_branch"),
    repositoryRemoteUrl: text("repository_remote_url"),
    repositoryGithubSlug: text("repository_github_slug"),
    repositoryPackageManagersJson: text(
      "repository_package_managers_json"
    ).notNull(),
    repositoryInstructionFilesJson: text(
      "repository_instruction_files_json"
    ).notNull(),
    defaultModel: text("default_model").notNull(),
    defaultReasoningLevel: text("default_reasoning_level").notNull(),
    runTimeoutSeconds: integer("run_timeout_seconds").notNull(),
    scheduleEnabled: integer("schedule_enabled", { mode: "boolean" }).notNull(),
    scheduleDailyTime: text("schedule_daily_time").notNull(),
    scheduleTimezone: text("schedule_timezone").notNull(),
    scheduledRunLimit: integer("scheduled_run_limit").notNull(),
    nextTaskNumber: integer("next_task_number").notNull(),
    createdAt: text("created_at").notNull(),
    updatedAt: text("updated_at").notNull(),
    removedAt: text("removed_at"),
  },
  (project) => [
    uniqueIndex("projects_active_key_unique")
      .on(project.key)
      .where(sql`${project.removedAt} IS NULL`),
    uniqueIndex("projects_active_repo_path_unique")
      .on(project.repoPath)
      .where(sql`${project.removedAt} IS NULL`),
  ]
)
