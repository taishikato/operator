import { appendFile, mkdir, readFile } from "node:fs/promises"
import { dirname } from "node:path"

import {
  createRunLogKey,
  resolveRunLogPath,
  type AppDataPaths,
} from "../app-data/app-data.ts"

export type RunLogSource = "operator" | "cursor"

export type RunLogEvent = {
  source: RunLogSource
  type: string
  payload?: Record<string, unknown>
  timestamp?: string
}

export type StoredRunLogEvent = {
  source: RunLogSource
  type: string
  payload: Record<string, unknown>
  timestamp: string
}

const SECRET_FIELD_PATTERN = /^(apiKey|token|secret|password|authorization)$/i
const CURSOR_API_KEY_PATTERN = /CURSOR_API_KEY\s*=\s*[^\s,;"']+/gi
const BEARER_TOKEN_PATTERN = /Bearer\s+[A-Za-z0-9._~+/=-]+/gi

export function createRawRunLogKey(runId: string) {
  return createRunLogKey(runId)
}

export async function appendRunLogEvent(
  paths: AppDataPaths,
  logKey: string,
  event: RunLogEvent
) {
  const logPath = resolveRunLogPath(paths, logKey)
  const line = JSON.stringify(toStoredEvent(event)) + "\n"

  await mkdir(dirname(logPath), { recursive: true })
  await appendFile(logPath, line, "utf8")
}

export async function readRunLogLines(paths: AppDataPaths, logKey: string) {
  return parseRunLogText(await readRawRunLogText(paths, logKey))
}

export async function readRawRunLogText(paths: AppDataPaths, logKey: string) {
  try {
    return await readFile(resolveRunLogPath(paths, logKey), "utf8")
  } catch (error) {
    if (isFileNotFoundError(error)) {
      return ""
    }

    throw error
  }
}

export function parseRunLogText(raw: string) {
  const lines = raw
    .split("\n")
    .filter((line) => line.trim().length > 0)

  return lines.flatMap((line, index) => {
    try {
      return [JSON.parse(line) as StoredRunLogEvent]
    } catch (error) {
      if (index === lines.length - 1) {
        return []
      }

      throw error
    }
  })
}

function toStoredEvent(event: RunLogEvent): StoredRunLogEvent {
  return {
    source: event.source,
    type: event.type,
    payload: redactValue(event.payload ?? {}) as Record<string, unknown>,
    timestamp: event.timestamp ?? new Date().toISOString(),
  }
}

function redactValue(value: unknown, fieldName?: string): unknown {
  if (fieldName && SECRET_FIELD_PATTERN.test(fieldName)) {
    return "[REDACTED]"
  }

  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item))
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [
        key,
        redactValue(item, key),
      ])
    )
  }

  if (typeof value === "string") {
    return value
      .replace(CURSOR_API_KEY_PATTERN, "CURSOR_API_KEY=[REDACTED]")
      .replace(BEARER_TOKEN_PATTERN, "Bearer [REDACTED]")
  }

  return value
}

function isFileNotFoundError(error: unknown) {
  return (
    error instanceof Error &&
    "code" in error &&
    (error as NodeJS.ErrnoException).code === "ENOENT"
  )
}
