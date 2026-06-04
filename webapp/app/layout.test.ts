import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

test("RootLayout includes the Sonner toaster", async () => {
  const source = await readFile(new URL("./layout.tsx", import.meta.url), "utf8")

  assert.match(source, /import\s+\{\s*Toaster\s+\}\s+from\s+"sonner"/)
  assert.match(source, /<Toaster\b/)
})

test("RootLayout includes a shared Operator home link", async () => {
  const source = await readFile(new URL("./layout.tsx", import.meta.url), "utf8")

  assert.match(source, /import\s+Link\s+from\s+"next\/link"/)
  assert.match(source, /href="\/"/)
  assert.match(source, />\s*Operator\s*</)
})

test("RootLayout includes a shared Add Project link", async () => {
  const source = await readFile(new URL("./layout.tsx", import.meta.url), "utf8")

  assert.match(source, /import\s+\{\s*Plus\s+\}\s+from\s+"lucide-react"/)
  assert.match(source, /href="\/projects\/new"/)
  assert.match(source, />\s*Add Project\s*</)
})
