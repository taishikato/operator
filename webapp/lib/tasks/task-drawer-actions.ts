import type { TaskStatus } from "./task-repository.ts"

export type TaskDrawerActionStateInput = {
  hasChanges: boolean
  isSaving: boolean
  isMovingReady: boolean
  isCreatingPullRequest?: boolean
  taskStatus: TaskStatus
  taskBranchName?: string | null
  pullRequestUrl?: string | null
}

export function getTaskDrawerActionState({
  hasChanges,
  isSaving,
  isMovingReady,
  isCreatingPullRequest = false,
  taskStatus,
  taskBranchName = null,
  pullRequestUrl = null,
}: TaskDrawerActionStateInput) {
  const isBusy = isSaving || isMovingReady || isCreatingPullRequest
  const createPullRequestVisible =
    taskStatus === "review" &&
    taskBranchName !== null &&
    pullRequestUrl === null

  return {
    isBusy,
    readyDisabled: isBusy || hasChanges || taskStatus === "ready",
    readyTitle: hasChanges
      ? "Save your changes before moving to Ready"
      : "Move to Ready",
    saveDisabled: !hasChanges || isBusy,
    discardDisabled: !hasChanges || isBusy,
    inputsDisabled: isBusy,
    createPullRequestVisible,
    createPullRequestDisabled: isBusy || hasChanges,
    createPullRequestTitle: hasChanges
      ? "Save your changes before creating a pull request"
      : "Create draft pull request",
  }
}
