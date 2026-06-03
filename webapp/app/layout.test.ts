import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

test("RootLayout includes the Sonner toaster", async () => {
  const source = await readFile(new URL("./layout.tsx", import.meta.url), "utf8")

  assert.match(source, /import\s+\{\s*Toaster\s+\}\s+from\s+"sonner"/)
  assert.match(source, /<Toaster\b/)
})
