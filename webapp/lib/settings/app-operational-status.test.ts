import assert from "node:assert/strict"
import { test } from "node:test"

test("getAppOperationalStatus reports app data, version, and Cursor key status without exposing secrets", async () => {
  const statusModule = await import("./app-operational-status.ts").catch(
    () => null
  )

  assert.ok(statusModule)

  const missing = statusModule.getAppOperationalStatus({
    appDataDir: "/Users/example/Library/Application Support/Operator",
    env: {},
    version: "0.0.1",
  })
  const configured = statusModule.getAppOperationalStatus({
    appDataDir: "/Users/example/Library/Application Support/Operator",
    env: { CURSOR_API_KEY: "secret-token-value" },
    version: "0.0.1",
  })

  assert.deepEqual(missing, {
    appDataDir: "/Users/example/Library/Application Support/Operator",
    cursorApiKeyStatus: "missing",
    version: "0.0.1",
  })
  assert.deepEqual(configured, {
    appDataDir: "/Users/example/Library/Application Support/Operator",
    cursorApiKeyStatus: "configured",
    version: "0.0.1",
  })
  assert.equal(JSON.stringify(configured).includes("secret-token-value"), false)
})
