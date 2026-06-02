import type { TaskStatus } from "./task-repository.ts"

export type TaskDrawerActionStateInput = {
  hasChanges: boolean
  isSaving: boolean
  isMovingReady: boolean
  taskStatus: TaskStatus
}

export function getTaskDrawerActionState({
  hasChanges,
  isSaving,
  isMovingReady,
  taskStatus,
}: TaskDrawerActionStateInput) {
  const isBusy = isSaving || isMovingReady

  return {
    isBusy,
    readyDisabled: isBusy || hasChanges || taskStatus === "ready",
    readyTitle: hasChanges
      ? "Save your changes before moving to Ready"
      : "Move to Ready",
    saveDisabled: !hasChanges || isBusy,
    discardDisabled: !hasChanges || isBusy,
    inputsDisabled: isBusy,
  }
}
