import { execFile } from "node:child_process"
import { promisify } from "node:util"

type BrowseProjectPathOptions = {
  platform?: NodeJS.Platform | string
  pickFolder?: () => Promise<string | null>
}

const execFileAsync = promisify(execFile)

export async function handleBrowseProjectPathRequest(
  options: BrowseProjectPathOptions = {}
) {
  const platform = options.platform ?? process.platform

  if (platform === "darwin") {
    const path = await pickFolderOrNull(
      options.pickFolder ?? pickFolderWithAppleScript
    )

    if (!path) {
      return Response.json(
        {
          error: {
            code: "browse_canceled",
            message: "Folder selection was canceled.",
          },
        },
        { status: 400 }
      )
    }

    return Response.json({ path })
  }

  return Response.json(
    {
      error: {
        code: "browse_not_supported",
        message: "Folder browsing is only available through the macOS backend.",
      },
    },
    { status: 501 }
  )
}

async function pickFolderOrNull(pickFolder: () => Promise<string | null>) {
  try {
    return await pickFolder()
  } catch (error) {
    if (isFolderPickerCancelError(error)) {
      return null
    }

    throw error
  }
}

async function pickFolderWithAppleScript() {
  const { stdout } = await execFileAsync("osascript", [
    "-e",
    'POSIX path of (choose folder with prompt "Choose a Git repository")',
  ])

  return stdout.trim() || null
}

function isFolderPickerCancelError(error: unknown) {
  if (!(error instanceof Error)) {
    return false
  }

  return (
    error.message.includes("User canceled") || error.message.includes("-128")
  )
}
