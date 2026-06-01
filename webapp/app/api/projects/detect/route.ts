import {
  handleDetectProjectRequest,
  resolveAddProjectApiOptions,
} from "../../../../lib/projects/add-project-api.ts"

export const runtime = "nodejs"

export async function POST(request: Request) {
  return handleDetectProjectRequest(
    request,
    await resolveAddProjectApiOptions()
  )
}
