import assert from "node:assert/strict"
import { test } from "node:test"

import { suggestProjectKey } from "./project-key.ts"

test("suggestProjectKey normalizes repository names into short uppercase keys", () => {
  assert.equal(suggestProjectKey("operator-web_app"), "OPERAT")
  assert.equal(suggestProjectKey("@scope/api.server"), "SCOPEA")
})

test("suggestProjectKey avoids invalid output for empty and symbolic repository names", () => {
  assert.equal(suggestProjectKey(""), "PROJ")
  assert.equal(suggestProjectKey("...---___"), "PROJ")
  assert.equal(suggestProjectKey("!!!agent-core???"), "AGENTC")
})
