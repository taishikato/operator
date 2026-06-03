"use client"

import { Copy, Download } from "lucide-react"
import { useEffect, useMemo, useState } from "react"

import { Button } from "@/components/ui/button"
import { shouldPollRunLog } from "@/lib/runs/run-status"

export function RawLogViewer({
  runId,
  initialStatus,
  initialRawLogText,
  pollIntervalMs = 2000,
}: {
  runId: string
  initialStatus: string
  initialRawLogText: string
  pollIntervalMs?: number
}) {
  const [status, setStatus] = useState(initialStatus)
  const [rawLogText, setRawLogText] = useState(initialRawLogText)
  const downloadHref = useMemo(
    () => `data:application/jsonl;charset=utf-8,${encodeURIComponent(rawLogText)}`,
    [rawLogText]
  )

  useEffect(() => {
    if (!shouldPollRunLog(status)) {
      return
    }

    const interval = setInterval(() => {
      void refreshRunLog()
    }, pollIntervalMs)

    return () => clearInterval(interval)

    async function refreshRunLog() {
      const response = await fetch(`/api/runs/${encodeURIComponent(runId)}`)

      if (!response.ok) {
        return
      }

      const body = (await response.json()) as {
        run?: { status?: string }
        rawLogText?: string
      }

      if (typeof body.rawLogText === "string") {
        setRawLogText(body.rawLogText)
      }

      if (typeof body.run?.status === "string") {
        setStatus(body.run.status)
      }
    }
  }, [pollIntervalMs, runId, status])

  async function copyRawLog() {
    await navigator.clipboard.writeText(rawLogText)
  }

  return (
    <section className="grid gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-mono text-xs text-muted-foreground">{runId}</p>
          <p className="mt-1 text-sm font-medium">{status}</p>
        </div>
        <div className="flex items-center gap-2">
          <Button type="button" variant="outline" onClick={copyRawLog}>
            <Copy data-icon="inline-start" />
            Copy
          </Button>
          <a
            href={downloadHref}
            download={`${runId}.jsonl`}
            className="inline-flex h-9 items-center gap-2 rounded-md border bg-background px-3 text-sm font-medium transition hover:bg-accent"
          >
            <Download className="h-4 w-4" />
            Download
          </a>
        </div>
      </div>
      <pre className="min-h-96 overflow-auto rounded-md border bg-muted/25 p-3 font-mono text-xs whitespace-pre-wrap">
        {rawLogText}
      </pre>
    </section>
  )
}
