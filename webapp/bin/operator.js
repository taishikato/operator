#!/usr/bin/env -S node --experimental-strip-types

import { runOperatorCliMain } from "../lib/cli/operator-cli.ts"

process.exitCode = await runOperatorCliMain()
