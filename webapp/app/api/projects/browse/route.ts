import { handleBrowseProjectPathRequest } from "../../../../lib/projects/browse-project-path.ts"

export const runtime = "nodejs"

export async function POST() {
  return handleBrowseProjectPathRequest()
}
