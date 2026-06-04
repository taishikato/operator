export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs") {
    return
  }

  const { startCliManagedServerRuntime } =
    await import("./lib/cli/operator-server-runtime.ts")
  await startCliManagedServerRuntime()
}
