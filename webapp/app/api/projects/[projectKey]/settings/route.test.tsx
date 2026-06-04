import assert from "node:assert/strict"
import { test } from "node:test"
import { mock } from "node:test"

const calls: Array<{
  request: Request
  projectKey: string
}> = []

mock.module("../../../../../lib/projects/project-settings-api.ts", {
  namedExports: {
    resolveProjectSettingsApiOptions: async ({
      projectKey,
    }: {
      projectKey: string
    }) => ({
      databasePath: "/tmp/operator-test.db",
      databaseStatus: "ready",
      projectKey,
    }),
    handleUpdateProjectSettingsRequest: async (
      request: Request,
      options: { projectKey: string }
    ) => {
      calls.push({ request, projectKey: options.projectKey })

      return Response.json({
        project: {
          defaults: {
            model: "gpt-5.5",
            reasoningLevel: "medium",
            runTimeoutSeconds: 1800,
          },
        },
      })
    },
  },
})

test("Project settings route delegates updates for the route Project key", async () => {
  const route = await import("./route.ts").catch(() => null)

  assert.ok(route)

  const response = await route.PATCH(
    jsonRequest({
      defaultModel: "gpt-5.5",
      defaultReasoningLevel: "medium",
      scheduleEnabled: true,
      scheduleDailyTime: "10:30",
      scheduleTimezone: "Asia/Tokyo",
      scheduledRunLimit: 4,
      runTimeoutSeconds: 1800,
    }),
    {
      params: Promise.resolve({ projectKey: "OP" }),
    }
  )
  const body = await response.json()

  assert.equal(response.status, 200)
  assert.equal(body.project.defaults.model, "gpt-5.5")
  assert.equal(calls.length, 1)
  assert.equal(calls[0]?.projectKey, "OP")
})

function jsonRequest(body: unknown) {
  return new Request("http://test", {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  })
}
