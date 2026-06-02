import {
  handleUpdateTaskBoardRequest,
  resolveTaskApiOptions,
} from "../../../../../../lib/tasks/task-api.ts"

export const runtime = "nodejs"

export async function PATCH(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as { projectKey: string }

  return handleUpdateTaskBoardRequest(
    request,
    await resolveTaskApiOptions({ projectKey })
  )
}
