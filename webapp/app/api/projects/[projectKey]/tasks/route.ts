import {
  handleCreateTaskRequest,
  handleListTasksRequest,
  resolveTaskApiOptions,
} from "../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function GET(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as { projectKey: string }

  return handleListTasksRequest(
    request,
    await resolveTaskApiOptions({ projectKey })
  )
}

export async function POST(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as { projectKey: string }

  return handleCreateTaskRequest(
    request,
    await resolveTaskApiOptions({ projectKey })
  )
}
