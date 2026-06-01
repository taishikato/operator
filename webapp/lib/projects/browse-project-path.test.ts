import assert from "node:assert/strict"
import { test } from "node:test"

import { handleBrowseProjectPathRequest } from "./browse-project-path.ts"

test("browse Project path returns a selected path from the macOS backend picker", async () => {
  const response = await handleBrowseProjectPathRequest({
    platform: "darwin",
    pickFolder: async () => "/Users/example/operator",
  })
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.deepEqual(body, {
    path: "/Users/example/operator",
  })
})

test("browse Project path treats a rejected macOS picker as a canceled selection", async () => {
  const response = await handleBrowseProjectPathRequest({
    platform: "darwin",
    pickFolder: async () => {
      throw new Error("User canceled.")
    },
  })
  const body = await response.json()

  assert.equal(response.status, 400)
  assert.deepEqual(body, {
    error: {
      code: "browse_canceled",
      message: "Folder selection was canceled.",
    },
  })
})

test("browse Project path falls back to manual input on unsupported platforms", async () => {
  const response = await handleBrowseProjectPathRequest({
    platform: "linux",
    pickFolder: async () => {
      throw new Error("should not be called")
    },
  })
  const body = await response.json()

  assert.equal(response.status, 501)
  assert.deepEqual(body, {
    error: {
      code: "browse_not_supported",
      message: "Folder browsing is only available through the macOS backend.",
    },
  })
})

test("browse Project path route exposes a POST endpoint", async () => {
  const route = await import("../../app/api/projects/browse/route.ts")

  assert.equal(typeof route.POST, "function")
  assert.equal(route.runtime, "nodejs")
})
