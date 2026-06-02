export type TaskInstructionFields = {
  title: string
  bodyMarkdown: string
  acceptanceCriteriaMarkdown: string
  modelOverride: string | null
  reasoningLevelOverride: string | null
}

export type TaskEditState = {
  saved: TaskInstructionFields
  draft: TaskInstructionFields
}

export function createTaskEditState(saved: TaskInstructionFields): TaskEditState {
  return {
    saved: { ...saved },
    draft: { ...saved },
  }
}

export function updateTaskEditDraft(
  state: TaskEditState,
  patch: Partial<TaskInstructionFields>
): TaskEditState {
  return {
    saved: state.saved,
    draft: {
      ...state.draft,
      ...patch,
    },
  }
}

export function discardTaskEditDraft(state: TaskEditState): TaskEditState {
  return {
    saved: state.saved,
    draft: { ...state.saved },
  }
}

export function hasUnsavedTaskEditChanges(state: TaskEditState) {
  return (
    state.saved.title !== state.draft.title ||
    state.saved.bodyMarkdown !== state.draft.bodyMarkdown ||
    state.saved.acceptanceCriteriaMarkdown !==
      state.draft.acceptanceCriteriaMarkdown ||
    state.saved.modelOverride !== state.draft.modelOverride ||
    state.saved.reasoningLevelOverride !== state.draft.reasoningLevelOverride
  )
}

export function getTaskEditSavePayload(state: TaskEditState) {
  return { ...state.draft }
}
