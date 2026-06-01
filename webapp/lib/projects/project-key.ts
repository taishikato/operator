const DEFAULT_PROJECT_KEY = "PROJ"
const MAX_PROJECT_KEY_LENGTH = 6

export function suggestProjectKey(repositoryName: string) {
  const key = repositoryName
    .replace(/^@/, "")
    .replace(/[^a-zA-Z0-9]/g, "")
    .toUpperCase()
    .slice(0, MAX_PROJECT_KEY_LENGTH)

  return key || DEFAULT_PROJECT_KEY
}
