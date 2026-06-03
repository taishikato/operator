export type ApiValidationIssue = {
  path: string[]
  code: string
  message: string
}

export async function parseJsonRequest(request: Request) {
  try {
    return { success: true as const, data: await request.json() }
  } catch {
    return { success: false as const }
  }
}

export function validationError(
  code: string,
  message: string,
  {
    status = 400,
    issues,
  }: {
    status?: number
    issues?: ApiValidationIssue[]
  } = {}
) {
  return Response.json(
    {
      error: {
        code,
        message,
        ...(issues ? { issues } : {}),
      },
    },
    { status }
  )
}

export function schemaApplyRequiredError() {
  return validationError(
    "schema_apply_required",
    "Operator database schema is out of date. Run the explicit database apply command or reset the local Operator database.",
    { status: 503 }
  )
}
