import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { mkdir, mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { test } from "node:test"

import { resolveAppDataPaths } from "../app-data/app-data.ts"

test("createRawRunLogKey returns a relative JSONL key under runs", async () => {
  const { createRawRunLogKey } = await getRawLog()
  const key = createRawRunLogKey("run_123")

  assert.equal(key, "runs/run_123.jsonl")
  assert.equal(key.startsWith("/"), false)
})

test("appendRunLogEvent appends redacted JSONL lines in chronological file order", async () => {
  const { appendRunLogEvent, createRawRunLogKey, readRunLogLines } =
    await getRawLog()
  const appDataRoot = await mkdtemp(join(tmpdir(), "operator-raw-log-"))
  const paths = resolveAppDataPaths({ appDataRoot })
  const logKey = createRawRunLogKey("run_456")

  await appendRunLogEvent(paths, logKey, {
    source: "operator",
    type: "run.created",
    payload: {
      apiKey: "CURSOR_API_KEY=cursor-secret",
      nested: {
        authorization: "Bearer abc.def.ghi",
      },
    },
  })
  await appendRunLogEvent(paths, logKey, {
    source: "cursor",
    type: "sdk.event",
    payload: {
      text: "second event",
      token: "plain-token",
      password: "pw",
    },
  })

  const raw = await readFile(join(appDataRoot, logKey), "utf8")
  const fileLines = raw.trimEnd().split("\n")
  const readLines = await readRunLogLines(paths, logKey)

  assert.equal(fileLines.length, 2)
  assert.deepEqual(readLines.map((line) => line.type), [
    "run.created",
    "sdk.event",
  ])
  assert.equal(readLines[0]?.source, "operator")
  assert.equal(readLines[1]?.source, "cursor")
  assert.equal(readLines[0]?.payload.apiKey, "[REDACTED]")
  assert.equal(
    (readLines[0]?.payload.nested as Record<string, unknown>).authorization,
    "[REDACTED]"
  )
  assert.equal(readLines[1]?.payload.token, "[REDACTED]")
  assert.equal(readLines[1]?.payload.password, "[REDACTED]")
  assert.doesNotMatch(raw, /cursor-secret|abc\.def\.ghi|plain-token|pw/)
})

test("readRunLogLines returns no events when the log file is missing", async () => {
  const { createRawRunLogKey, readRunLogLines } = await getRawLog()
  const appDataRoot = await mkdtemp(join(tmpdir(), "operator-raw-log-"))
  const paths = resolveAppDataPaths({ appDataRoot })

  const lines = await readRunLogLines(paths, createRawRunLogKey("missing"))

  assert.deepEqual(lines, [])
})

test("readRunLogLines ignores a partially written trailing JSONL line", async () => {
  const { createRawRunLogKey, readRunLogLines } = await getRawLog()
  const appDataRoot = await mkdtemp(join(tmpdir(), "operator-raw-log-"))
  const paths = resolveAppDataPaths({ appDataRoot })
  const logKey = createRawRunLogKey("partial")
  const logPath = join(appDataRoot, logKey)

  await mkdir(dirname(logPath), { recursive: true })
  await writeFile(
    logPath,
    [
      JSON.stringify({
        source: "operator",
        type: "run.created",
        payload: {},
        timestamp: "2026-06-01T00:00:00.000Z",
      }),
      '{"source":"cursor"',
    ].join("\n"),
    "utf8"
  )

  const lines = await readRunLogLines(paths, logKey)

  assert.deepEqual(
    lines.map((line) => line.type),
    ["run.created"]
  )
})

async function getRawLog() {
  try {
    return await import("./raw-log.ts")
  } catch {
    assert.fail("raw-log module is not implemented yet")
  }
}
