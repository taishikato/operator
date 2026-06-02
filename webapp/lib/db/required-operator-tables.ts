import { getTableName } from "drizzle-orm"

import { operatorSchemaTables } from "./schema.ts"

export function getRequiredOperatorTableNames() {
  return operatorSchemaTables.map(getTableName)
}
