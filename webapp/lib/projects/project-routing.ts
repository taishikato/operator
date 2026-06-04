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
  void _projects

  return null
}
