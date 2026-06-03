import type { TaskStatus } from "./task-repository.ts"

export type TaskDrawerActionStateInput = {
  hasChanges: boolean
  isSaving: boolean
  isMovingReady: boolean
  isCreatingPullRequest?: boolean
  taskStatus: TaskStatus
  taskBranchName?: string | null
  pullRequestUrl?: string | null
  pullRequestTitle?: string | null
}

export function getTaskDrawerActionState({
  hasChanges,
  isSaving,
  isMovingReady,
  isCreatingPullRequest = false,
  taskStatus,
  taskBranchName = null,
  pullRequestUrl = null,
  pullRequestTitle = null,
}: TaskDrawerActionStateInput) {
  const isBusy = isSaving || isMovingReady || isCreatingPullRequest
  const hasEmptyPullRequestTitle =
    pullRequestTitle !== null && pullRequestTitle.trim().length === 0
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
    createPullRequestDisabled: isBusy || hasChanges || hasEmptyPullRequestTitle,
    createPullRequestTitle: hasChanges
      ? "Save your changes before creating a pull request"
      : hasEmptyPullRequestTitle
        ? "Enter a pull request title"
        : "Create draft pull request",
  }
}
