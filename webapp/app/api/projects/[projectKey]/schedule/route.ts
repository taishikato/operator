import {
  handleUpdateProjectScheduleRequest,
  resolveProjectScheduleApiOptions,
} from "../../../../../lib/projects/project-schedule-api.ts"

export const runtime = "nodejs"

export async function PATCH(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as {
    projectKey: string
  }

  return handleUpdateProjectScheduleRequest(request, {
    ...(await resolveProjectScheduleApiOptions({ projectKey })),
  })
}
