import { readFile } from "node:fs/promises"
import { test } from "node:test"
import assert from "node:assert/strict"

test("package exposes the local operator CLI without changing the development script", async () => {
  const packageJson = JSON.parse(await readFile("package.json", "utf8"))

  assert.equal(packageJson.bin.operator, "./bin/operator.js")
  assert.equal(packageJson.scripts.dev, "next dev")
})
