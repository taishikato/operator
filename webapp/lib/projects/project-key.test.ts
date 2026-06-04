import assert from "node:assert/strict"
import { test } from "node:test"

import { suggestProjectKey } from "./project-key.ts"

test("suggestProjectKey normalizes repository names into short lowercase keys", () => {
  assert.equal(suggestProjectKey("operator-web_app"), "operator-web-app")
  assert.equal(suggestProjectKey("@scope/api.server"), "scope-api-server")
})

test("suggestProjectKey avoids invalid output for empty and symbolic repository names", () => {
  assert.equal(suggestProjectKey(""), "project")
  assert.equal(suggestProjectKey("...---___"), "project")
  assert.equal(suggestProjectKey("!!!agent-core???"), "agent-core")
})
