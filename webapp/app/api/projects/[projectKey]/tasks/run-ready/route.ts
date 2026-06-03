import {
  handleRunReadyTasksRequest,
  resolveTaskApiOptions,
} from "../../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function POST(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as {
    projectKey: string
  }

  return handleRunReadyTasksRequest(request, {
    ...(await resolveTaskApiOptions({ projectKey })),
  })
}
