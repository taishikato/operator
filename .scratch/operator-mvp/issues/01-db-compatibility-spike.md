Status: ready-for-agent
Type: HITL

# DB compatibility spike for Turso, Drizzle, and Atlas

## Parent

.scratch/operator-mvp/PRD.md

## What to build

Verify whether the selected local database stack can support Operator's schema workflow before the rest of the persistence layer depends on it. The spike should prove that Turso local storage, Drizzle beta schema definitions, and Atlas declarative apply can create and evolve a minimal Operator database. If the stack cannot support this safely, document the failure and propose the smallest alternative schema apply path.

## Acceptance criteria

- [x] A minimal Project-like table can be defined through the chosen Drizzle beta schema approach.
- [x] Atlas declarative apply can create or update the local Turso database from that schema, or the incompatibility is clearly documented.
- [x] The result states whether Atlas remains the selected schema apply tool for the MVP.
- [x] If Atlas does not remain selected, the issue records the replacement apply path and why it better fits the MVP. N/A: Atlas remains selected.
- [x] No application persistence code is built on an unverified schema apply assumption.

## Blocked by

None - can start immediately

## Comments

### Spike result

Turso local storage and Drizzle beta are compatible for a minimal Project-like table.

Verified behavior:

- A Drizzle beta SQLite schema defines `spike_projects` in `webapp/spikes/db-compatibility/schema.ts`.
- `@tursodatabase/database` can create a local database file.
- `drizzle-orm/tursodatabase/database` can insert and select rows against that table.
- `pnpm test` passes the compatibility test in `webapp/spikes/db-compatibility/turso-drizzle-spike.test.ts`.

Drizzle Kit beta can export SQL from the schema:

```sh
pnpm exec drizzle-kit export --dialect sqlite --schema ./spikes/db-compatibility/schema.ts
```

Observed SQL:

```sql
CREATE TABLE `spike_projects` (
	`id` text PRIMARY KEY,
	`key` text NOT NULL UNIQUE,
	`name` text NOT NULL,
	`repo_path` text NOT NULL UNIQUE
);
```

Earlier result before Atlas was installed:

```sh
atlas version
# zsh:1: command not found: atlas
```

After Atlas was installed, the compatibility check was rerun with:

```sh
atlas version
# atlas version v1.2.1-a9eeb8b-canary

pnpm exec drizzle-kit export --dialect sqlite --schema ./spikes/db-compatibility/schema.ts > /tmp/operator-spike-schema.sql

atlas schema apply \
  -u "sqlite:///tmp/operator-atlas-spike.db" \
  --to "file:///tmp/operator-spike-schema.sql" \
  --dev-url "sqlite://dev?mode=memory" \
  --auto-approve
```

Atlas successfully planned and applied the Drizzle-exported SQL to a database file first created by `@tursodatabase/database`. The resulting database was readable and writable through the Turso driver.

Atlas update behavior was also verified by applying a second desired SQL file that added a nullable `description` column. `atlas schema apply` planned and applied:

```sql
ALTER TABLE `spike_projects` ADD COLUMN `description` text NULL;
```

The updated database was then writable/readable through `@tursodatabase/database`.

Atlas should remain the selected schema apply tool for the MVP, with Drizzle schema as the source of truth and Drizzle Kit SQL export as the bridge into Atlas declarative apply.

Caveat: Atlas correctly planned a dangerous update for adding a `NOT NULL` column without a default to a table with existing rows, and only surfaced detailed diagnostics behind `atlas login`. For MVP schema changes, keep explicit review/dry-run output in the `operator db apply` path and avoid unsafe non-null additions without defaults.
