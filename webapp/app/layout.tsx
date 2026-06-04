import { Geist_Mono, Inter } from "next/font/google"
import { Plus } from "lucide-react"
import Link from "next/link"
import { Toaster } from "sonner"

import "./globals.css"
import { ThemeProvider } from "@/components/theme-provider"
import { cn } from "@/lib/utils"

const inter = Inter({ subsets: ["latin"], variable: "--font-sans" })

const fontMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
})

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={cn(
        "antialiased",
        fontMono.variable,
        "font-sans",
        inter.variable
      )}
    >
      <body>
        <ThemeProvider>
          <header className="flex items-center justify-between gap-3 border-b bg-background px-4 py-4 sm:px-6 lg:px-8">
            <Link
              href="/"
              className="text-sm font-semibold tracking-normal text-muted-foreground transition hover:text-foreground"
            >
              Operator
            </Link>
            <Link
              href="/projects/new"
              className="inline-flex h-8 items-center gap-1.5 rounded-md border bg-background px-2.5 text-sm font-medium transition hover:bg-muted"
            >
              <Plus className="h-4 w-4" />
              Add Project
            </Link>
          </header>
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  )
}
