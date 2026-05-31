import assert from "node:assert/strict"
import { mkdtemp, stat } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { test } from "node:test"

import {
  createRunLogKey,
  ensureAppData,
  resolveAppDataPaths,
  resolveRunLogPath,
} from "./app-data.ts"

test("resolveAppDataPaths returns deterministic database and run-log paths under an explicit root", () => {
  const paths = resolveAppDataPaths({
    appDataRoot: join("/tmp", "operator-app-data"),
  })

  assert.deepEqual(paths, {
    appDataDir: join("/tmp", "operator-app-data"),
    databasePath: join("/tmp", "operator-app-data", "operator.db"),
    runLogsDir: join("/tmp", "operator-app-data", "runs"),
  })
})

test("resolveAppDataPaths resolves OS app data roots deterministically", () => {
  assert.equal(
    resolveAppDataPaths({
      platform: "darwin",
      env: { HOME: "/Users/operator" },
    }).appDataDir,
    join("/Users/operator", "Library", "Application Support", "Operator")
  )

  assert.equal(
    resolveAppDataPaths({
      platform: "linux",
      env: { HOME: "/home/operator" },
    }).appDataDir,
    join("/home/operator", ".local", "share", "operator")
  )

  assert.equal(
    resolveAppDataPaths({
      platform: "win32",
      env: { APPDATA: "C:\\Users\\operator\\AppData\\Roaming" },
    }).appDataDir,
    join("C:\\Users\\operator\\AppData\\Roaming", "Operator")
  )
})

test("ensureAppData creates the app data and run-log directories", async () => {
  const directory = await mkdtemp(join(tmpdir(), "operator-app-data-"))
  const paths = resolveAppDataPaths({
    appDataRoot: join(directory, "nested", "operator"),
  })

  await ensureAppData(paths)

  assert.equal((await stat(paths.appDataDir)).isDirectory(), true)
  assert.equal((await stat(paths.runLogsDir)).isDirectory(), true)
})

test("run logs use relative keys that resolve inside the app data directory", () => {
  const paths = resolveAppDataPaths({
    appDataRoot: join("/tmp", "operator-app-data"),
  })
  const logKey = createRunLogKey("run_01")

  assert.equal(logKey, "runs/run_01.jsonl")
  assert.equal(
    resolveRunLogPath(paths, logKey),
    join(paths.runLogsDir, "run_01.jsonl")
  )
})

test("resolveRunLogPath rejects absolute or escaping log keys", () => {
  const paths = resolveAppDataPaths({
    appDataRoot: join("/tmp", "operator-app-data"),
  })

  assert.throws(() => resolveRunLogPath(paths, "/tmp/run_01.jsonl"), {
    message: "Run log key must be relative to Operator app data",
  })
  assert.throws(() => resolveRunLogPath(paths, "runs/../outside.jsonl"), {
    message: "Run log key must stay inside the Operator run-log directory",
  })
})
