import {
  handleCreateTaskPullRequestRequest,
  handlePrepareTaskPullRequestRequest,
  resolveTaskApiOptions,
} from "../../../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function GET(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey, taskDisplayId } = (await params) as {
    projectKey: string
    taskDisplayId: string
  }

  return handlePrepareTaskPullRequestRequest(request, {
    ...(await resolveTaskApiOptions({ projectKey })),
    taskDisplayId,
  })
}

export async function POST(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey, taskDisplayId } = (await params) as {
    projectKey: string
    taskDisplayId: string
  }

  return handleCreateTaskPullRequestRequest(request, {
    ...(await resolveTaskApiOptions({ projectKey })),
    taskDisplayId,
  })
}
