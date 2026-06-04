import { Geist_Mono, Inter } from "next/font/google"
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
          <header className="border-b bg-background px-4 py-4 sm:px-6 lg:px-8">
            <Link
              href="/"
              className="text-sm font-semibold tracking-normal text-muted-foreground transition hover:text-foreground"
            >
              Operator
            </Link>
          </header>
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  )
}
