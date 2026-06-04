import { GlobalRegistrator } from "@happy-dom/global-registrator"

import assert from "node:assert/strict"
import { afterEach, test } from "node:test"

import { cleanup, render } from "@testing-library/react"
import { mock } from "node:test"

GlobalRegistrator.register()

afterEach(() => {
  cleanup()
})

mock.module("next/navigation", {
  namedExports: {
    useRouter: () => ({
      push: (route: string) => {
        void route
      },
    }),
  },
})

test("AddProjectForm does not require a separate detection step", async () => {
  const { AddProjectForm } = await import("./add-project-form.tsx")

  const view = render(<AddProjectForm />)

  assert.equal(view.queryByRole("button", { name: "Detect" }), null)
})
