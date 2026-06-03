import assert from "node:assert/strict"
import { test } from "node:test"

import {
  createProjectScheduler,
  selectScheduledProjectFire,
} from "./project-scheduler.ts"

test("selectScheduledProjectFire fires when a running scheduler crosses the Project-local daily time", () => {
  const fire = selectScheduledProjectFire({
    project: scheduledProject({
      dailyTime: "09:00",
      timezone: "Asia/Tokyo",
    }),
    previousTickAt: new Date("2026-06-02T23:59:00.000Z"),
    now: new Date("2026-06-03T00:00:00.000Z"),
  })

  assert.deepEqual(fire, {
    projectId: "project_01",
    projectKey: "OP",
    localDate: "2026-06-03",
    limit: 1,
  })
})

test("selectScheduledProjectFire uses the Project timezone instead of the host timezone", () => {
  const fire = selectScheduledProjectFire({
    project: scheduledProject({
      dailyTime: "09:00",
      timezone: "America/New_York",
    }),
    previousTickAt: new Date("2026-06-03T12:59:00.000Z"),
    now: new Date("2026-06-03T13:00:00.000Z"),
  })

  assert.equal(fire?.localDate, "2026-06-03")
})

test("selectScheduledProjectFire does not catch up a missed schedule on startup", () => {
  const fire = selectScheduledProjectFire({
    project: scheduledProject({
      dailyTime: "09:00",
      timezone: "Asia/Tokyo",
    }),
    previousTickAt: null,
    now: new Date("2026-06-03T01:00:00.000Z"),
  })

  assert.equal(fire, null)
})

test("selectScheduledProjectFire prevents duplicate daily fires by Project-local date", () => {
  const fire = selectScheduledProjectFire({
    project: scheduledProject({
      dailyTime: "09:00",
      timezone: "Asia/Tokyo",
      lastScheduledLocalDate: "2026-06-03",
    }),
    previousTickAt: new Date("2026-06-02T23:59:00.000Z"),
    now: new Date("2026-06-03T00:00:00.000Z"),
  })

  assert.equal(fire, null)
})

test("Project scheduler tick does not catch up a missed schedule on startup", async () => {
  const batchCalls: unknown[] = []
  const markedDates: string[] = []
  const scheduler = createProjectScheduler({
    projects: {
      async listSchedulableProjects() {
        return [
          scheduledProject({
            dailyTime: "09:00",
            timezone: "Asia/Tokyo",
            scheduledRunLimit: 2,
          }),
        ]
      },
      async markScheduledLocalDateFired(_projectId, localDate) {
        markedDates.push(localDate)
      },
    },
    batches: {
      async runReadyTaskBatch(input) {
        batchCalls.push(input)
        return { status: "completed", results: [] }
      },
    },
  })

  await scheduler.tick(new Date("2026-06-03T01:00:00.000Z"))

  assert.deepEqual(batchCalls, [])
  assert.deepEqual(markedDates, [])
})

test("Project scheduler tick runs due Projects with the Project scheduled run limit and marks the local date fired", async () => {
  const batchCalls: unknown[] = []
  const markedDates: string[] = []
  const scheduler = createProjectScheduler({
    projects: {
      async listSchedulableProjects() {
        return [
          scheduledProject({
            dailyTime: "09:00",
            timezone: "Asia/Tokyo",
            scheduledRunLimit: 2,
          }),
        ]
      },
      async markScheduledLocalDateFired(_projectId, localDate) {
        markedDates.push(localDate)
      },
    },
    batches: {
      async runReadyTaskBatch(input) {
        batchCalls.push(input)
        return { status: "completed", results: [] }
      },
    },
  })

  await scheduler.tick(new Date("2026-06-02T23:59:00.000Z"))
  await scheduler.tick(new Date("2026-06-03T00:00:00.000Z"))

  assert.deepEqual(batchCalls, [
    {
      projectId: "project_01",
      projectKey: "OP",
      limit: 2,
    },
  ])
  assert.deepEqual(markedDates, ["2026-06-03"])
})

test("Project scheduler tick leaves the local date unmarked when the Project batch is already running", async () => {
  const markedDates: string[] = []
  const scheduler = createProjectScheduler({
    projects: {
      async listSchedulableProjects() {
        return [
          scheduledProject({
            dailyTime: "09:00",
            timezone: "Asia/Tokyo",
          }),
        ]
      },
      async markScheduledLocalDateFired(_projectId, localDate) {
        markedDates.push(localDate)
      },
    },
    batches: {
      async runReadyTaskBatch() {
        return { status: "already_running", results: [] }
      },
    },
  })

  await scheduler.tick(new Date("2026-06-02T23:59:00.000Z"))
  await scheduler.tick(new Date("2026-06-03T00:00:00.000Z"))

  assert.deepEqual(markedDates, [])
})

test("Project scheduler tick leaves the local date unmarked when the Project batch stops before completing", async () => {
  const markedDates: string[] = []
  const scheduler = createProjectScheduler({
    projects: {
      async listSchedulableProjects() {
        return [
          scheduledProject({
            dailyTime: "09:00",
            timezone: "Asia/Tokyo",
          }),
        ]
      },
      async markScheduledLocalDateFired(_projectId, localDate) {
        markedDates.push(localDate)
      },
    },
    batches: {
      async runReadyTaskBatch() {
        return {
          status: "stopped",
          results: [
            {
              status: "blocked",
              blockedReason: "timeout",
              taskBranchName: "operator/op-1",
              runId: "run_01",
            },
          ],
        }
      },
    },
  })

  await scheduler.tick(new Date("2026-06-02T23:59:00.000Z"))
  await scheduler.tick(new Date("2026-06-03T00:00:00.000Z"))

  assert.deepEqual(markedDates, [])
})

test("Project scheduler tick leaves the local date unmarked when the Project batch throws", async () => {
  const markedDates: string[] = []
  const scheduler = createProjectScheduler({
    projects: {
      async listSchedulableProjects() {
        return [
          scheduledProject({
            dailyTime: "09:00",
            timezone: "Asia/Tokyo",
          }),
        ]
      },
      async markScheduledLocalDateFired(_projectId, localDate) {
        markedDates.push(localDate)
      },
    },
    batches: {
      async runReadyTaskBatch() {
        throw new Error("batch failed")
      },
    },
  })

  await scheduler.tick(new Date("2026-06-02T23:59:00.000Z"))
  await assert.rejects(
    scheduler.tick(new Date("2026-06-03T00:00:00.000Z")),
    /batch failed/
  )

  assert.deepEqual(markedDates, [])
})

function scheduledProject(
  schedule: Partial<{
    enabled: boolean
    dailyTime: string
    timezone: string
    scheduledRunLimit: number
    lastScheduledLocalDate: string | null
  }> = {}
) {
  return {
    id: "project_01",
    key: "OP",
    schedule: {
      enabled: true,
      dailyTime: "09:00",
      timezone: "UTC",
      scheduledRunLimit: 1,
      lastScheduledLocalDate: null,
      ...schedule,
    },
  }
}
