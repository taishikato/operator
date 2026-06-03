const activeProjectIds = new Set<string>()

export async function runWithProjectExecutionLock<T>(
  projectId: string,
  callback: () => Promise<T>
): Promise<
  | {
      status: "acquired"
      value: T
    }
  | {
      status: "already_running"
    }
> {
  if (activeProjectIds.has(projectId)) {
    return { status: "already_running" }
  }

  activeProjectIds.add(projectId)

  try {
    return { status: "acquired", value: await callback() }
  } finally {
    activeProjectIds.delete(projectId)
  }
}
