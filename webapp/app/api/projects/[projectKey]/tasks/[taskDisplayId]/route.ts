import {
  handleUpdateTaskRequest,
  resolveTaskApiOptions,
} from "../../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function PATCH(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey, taskDisplayId } = (await params) as {
    projectKey: string
    taskDisplayId: string
  }

  return handleUpdateTaskRequest(request, {
    ...(await resolveTaskApiOptions({ projectKey })),
    taskDisplayId,
  })
}
