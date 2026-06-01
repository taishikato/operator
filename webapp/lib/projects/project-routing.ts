import type { Project } from "./project-repository.ts"

type InitialProjectRouteSource = {
  listActiveProjects: () => Promise<Project[]>
}

export async function loadInitialProjectRoute(
  source: InitialProjectRouteSource
) {
  return selectInitialProjectRoute(await source.listActiveProjects())
}

export function selectInitialProjectRoute(_projects: Project[]) {
  if (_projects.length === 0) {
    return null
  }

  const latestProject = _projects.toSorted((left, right) =>
    left.createdAt.localeCompare(right.createdAt)
  ).at(-1)

  return `/projects/${latestProject?.key}`
}
