import { getTableName } from "drizzle-orm"
import assert from "node:assert/strict"
import { test } from "node:test"

import {
  operatorMetadata,
  operatorSchemaTables,
  projects,
  runs,
  tasks,
} from "./schema.ts"
import { getRequiredOperatorTableNames } from "./required-operator-tables.ts"

test("getRequiredOperatorTableNames derives table names from the Drizzle schema", () => {
  assert.deepEqual(getRequiredOperatorTableNames(), [
    getTableName(operatorMetadata),
    getTableName(projects),
    getTableName(tasks),
    getTableName(runs),
  ])
})

test("operatorSchemaTables includes every exported Operator table", () => {
  assert.deepEqual(
    operatorSchemaTables.map(getTableName).sort(),
    getRequiredOperatorTableNames().sort()
  )
})
