import assert from "node:assert/strict"
import { test } from "node:test"

import { taskDrawerRemountKey } from "./task-drawer-mount.ts"

test("task drawer remount key changes when selected task changes", () => {
  assert.equal(taskDrawerRemountKey("OP-1"), "OP-1")
  assert.notEqual(taskDrawerRemountKey("OP-1"), taskDrawerRemountKey("OP-2"))
})
