export function shouldStartSchedulerFromWebRequest(
  env: Partial<NodeJS.ProcessEnv> = process.env
) {
  return env.OPERATOR_CLI_MANAGED_START !== "1"
}
