import { text, sqliteTable } from "drizzle-orm/sqlite-core"

export const operatorMetadata = sqliteTable("operator_metadata", {
  key: text("key").notNull().primaryKey(),
  value: text("value").notNull(),
  updatedAt: text("updated_at").notNull(),
})
