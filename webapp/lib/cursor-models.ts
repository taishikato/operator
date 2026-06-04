export const cursorModelOptions = [
  {
    label: "GPT 5.5",
    value: "gpt-5.5",
    supportsReasoning: true,
  },
  {
    label: "Opus 4.8",
    value: "opus-4.8",
    supportsReasoning: true,
  },
  {
    label: "Opus 4.7",
    value: "opus-4.7",
    supportsReasoning: true,
  },
  {
    label: "Composer 2.5",
    value: "composer-2.5",
    supportsReasoning: false,
  },
] as const

export const cursorReasoningLevels = [
  "default",
  "low",
  "medium",
  "high",
] as const

export type CursorModel = (typeof cursorModelOptions)[number]["value"]
export type CursorReasoningLevel = (typeof cursorReasoningLevels)[number]

export const defaultCursorModel = cursorModelOptions[0].value
export const defaultCursorReasoningLevel = "medium"
export const nonReasoningCursorReasoningLevel = "default"

const cursorModelValues = new Set<string>(
  cursorModelOptions.map((option) => option.value)
)

export function isCursorModel(value: string): value is CursorModel {
  return cursorModelValues.has(value)
}

export function normalizeCursorModel(value: string): CursorModel {
  return isCursorModel(value) ? value : defaultCursorModel
}

export function cursorModelSupportsReasoning(value: string) {
  return (
    cursorModelOptions.find((option) => option.value === value)
      ?.supportsReasoning ?? false
  )
}

export function normalizeCursorReasoningLevel({
  model,
  reasoningLevel,
}: {
  model: string
  reasoningLevel: string
}): CursorReasoningLevel {
  if (!cursorModelSupportsReasoning(model)) {
    return nonReasoningCursorReasoningLevel
  }

  if (
    reasoningLevel === "low" ||
    reasoningLevel === "medium" ||
    reasoningLevel === "high"
  ) {
    return reasoningLevel
  }

  return defaultCursorReasoningLevel
}
