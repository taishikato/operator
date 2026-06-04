const DEFAULT_PROJECT_KEY = "project"
const MAX_PROJECT_KEY_LENGTH = 32

export function suggestProjectKey(repositoryName: string) {
  const key = repositoryName
    .replace(/^@/, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, MAX_PROJECT_KEY_LENGTH)
    .replace(/-+$/g, "")

  return key || DEFAULT_PROJECT_KEY
}
