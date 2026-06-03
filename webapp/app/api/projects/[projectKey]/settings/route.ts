import {
  handleUpdateProjectSettingsRequest,
  resolveProjectSettingsApiOptions,
} from "../../../../../lib/projects/project-settings-api.ts"

export const runtime = "nodejs"

export async function PATCH(
  request: Request,
  { params }: { params: Promise<unknown> }
) {
  const { projectKey } = (await params) as {
    projectKey: string
  }

  return handleUpdateProjectSettingsRequest(request, {
    ...(await resolveProjectSettingsApiOptions({ projectKey })),
  })
}
