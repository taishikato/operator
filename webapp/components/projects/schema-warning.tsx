export function SchemaWarning() {
  return (
    <div
      role="alert"
      className="rounded-lg border border-amber-500/35 bg-amber-500/10 p-4 text-sm text-amber-950 dark:text-amber-100"
    >
      Operator database schema is out of date. Run the explicit database apply
      command or reset the local Operator database.
    </div>
  )
}
