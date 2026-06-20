# Cursor Cloud Agent API Spike

Status: historical REST spike. The MVP runtime now uses the official Cursor SDK through the bundled Node helper.

The REST contract below was verified against Cursor's official Cloud Agents API docs on 2026-06-19:

- Base URL: `https://api.cursor.com`
- Create agent endpoint: `POST /v1/agents`
- Authentication: HTTP Basic with the Cursor API key as username and an empty password, matching `curl -u YOUR_API_KEY:`
- Content type: `application/json`
- Create request fields:
  - `prompt.text`: prompt text exactly as written
  - `model.id`: MVP uses fixed `composer-2.5`; docs examples use the same model object shape
  - `repos[0].url`: GitHub repository URL
  - `repos[0].startingRef`: remote default branch/ref
  - `autoCreatePR`: task-level boolean
- Success response mapping:
  - `agent.id` -> Cursor agent id
  - `agent.url` -> web URL for "Open in Cursor"
  - `run.id` -> initial run id
- Error mapping:
  - 401/403 -> authentication failure
  - 400/404/409/422 -> validation/request failure
  - malformed JSON or missing fields -> malformed response
  - transport errors -> network failure

Uncertainties:

- The official examples show `composer-2` and model params in the docs payload, while the PRD fixes this app to `composer-2.5`. The request object still uses `model.id`, so the app keeps `composer-2.5` as configured by product decision.
- The docs include optional fields such as `mcpServers`, `envVars`, `skipReviewerRequest`, and follow-up run endpoints. These are out of scope for the MVP.

Current runtime decision:

- Cursor Operator starts and waits for Cloud Agent runs through `@cursor/sdk` in `Resources/CursorSDKHelper/cursor-sdk-helper.mjs`.
- The app requires a user-installed Node.js 22.13+ runtime and does not bundle Node.
- The Swift REST client remains as historical spike/prototype code, but it is not the preferred MVP runtime path because the product direction requires SDK start and wait semantics.
- SDK helper startup can take multiple minutes before Cursor returns a run reference; the app should show an in-progress state during send and use a startup timeout long enough for slow Cloud Agent creation.

Sources:

- Cursor Cloud Agents API docs: https://cursor.com/docs/cloud-agent/api/endpoints
- Cursor SDK launch post: https://cursor.com/blog/typescript-sdk
