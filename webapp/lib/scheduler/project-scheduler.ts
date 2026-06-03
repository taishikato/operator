import type { Project } from "../projects/project-repository.ts"
import type { ProjectBatchResult } from "./project-batch-runner.ts"

export type ScheduledProjectFire = {
  projectId: string
  projectKey: string
  localDate: string
  limit: number
}

type SchedulableProject = Pick<Project, "id" | "key" | "schedule">

type SchedulerProjectRepository = {
  listSchedulableProjects(): Promise<SchedulableProject[]>
  markScheduledLocalDateFired(
    projectId: string,
    localDate: string
  ): Promise<unknown>
}

type SchedulerBatchRunner = {
  runReadyTaskBatch(input: {
    projectId: string
    projectKey: string
    limit: number
  }): Promise<ProjectBatchResult>
}

export function createProjectScheduler({
  projects,
  batches,
}: {
  projects: SchedulerProjectRepository
  batches: SchedulerBatchRunner
}) {
  let previousTickAt: Date | null = null

  return {
    async tick(now = new Date()) {
      const tickBefore = previousTickAt
      previousTickAt = now

      const schedulableProjects = await projects.listSchedulableProjects()
      const fires = schedulableProjects
        .map((project) =>
          selectScheduledProjectFire({
            project,
            previousTickAt: tickBefore,
            now,
          })
        )
        .filter((fire): fire is ScheduledProjectFire => fire !== null)

      await Promise.all(
        fires.map(async (fire) => {
          await projects.markScheduledLocalDateFired(
            fire.projectId,
            fire.localDate
          )
          await batches.runReadyTaskBatch({
            projectId: fire.projectId,
            projectKey: fire.projectKey,
            limit: fire.limit,
          })
        })
      )

      return { fires }
    },
  }
}

export function selectScheduledProjectFire({
  project,
  previousTickAt,
  now,
}: {
  project: SchedulableProject
  previousTickAt: Date | null
  now: Date
}): ScheduledProjectFire | null {
  if (!project.schedule.enabled || previousTickAt === null) {
    return null
  }

  const localNow = projectLocalDateTime(now, project.schedule.timezone)

  if (project.schedule.lastScheduledLocalDate === localNow.date) {
    return null
  }

  const localPrevious = projectLocalDateTime(
    previousTickAt,
    project.schedule.timezone
  )
  const scheduledStamp = `${localNow.date}T${project.schedule.dailyTime}`

  if (
    `${localPrevious.date}T${localPrevious.time}` >= scheduledStamp ||
    `${localNow.date}T${localNow.time}` < scheduledStamp
  ) {
    return null
  }

  return {
    projectId: project.id,
    projectKey: project.key,
    localDate: localNow.date,
    limit: project.schedule.scheduledRunLimit,
  }
}

function projectLocalDateTime(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-US", {
    calendar: "gregory",
    numberingSystem: "latn",
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(date)
  const part = (type: Intl.DateTimeFormatPartTypes) => {
    const value = parts.find((item) => item.type === type)?.value

    if (!value) {
      throw new Error(`Could not read ${type} from local date format.`)
    }

    return value
  }

  return {
    date: `${part("year")}-${part("month")}-${part("day")}`,
    time: `${part("hour")}:${part("minute")}`,
  }
}
