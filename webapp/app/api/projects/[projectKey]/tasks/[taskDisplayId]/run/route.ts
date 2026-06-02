import {
  handleRunTaskNowRequest,
  resolveTaskApiOptions,
} from "../../../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function POST(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey, taskDisplayId } = (await params) as {
    projectKey: string
    taskDisplayId: string
  }

  return handleRunTaskNowRequest(request, {
    ...(await resolveTaskApiOptions({ projectKey })),
    taskDisplayId,
  })
}
