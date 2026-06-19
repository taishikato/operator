# Cursor Cloud Agent API Spike

Status: REST remains the MVP implementation path.

Verified against Cursor's official Cloud Agents API docs on 2026-06-19:

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

Fallback condition:

- If `POST /v1/agents` rejects `composer-2.5` or changes required fields in a way the Swift REST client cannot keep stable, use a Node helper with `@cursor/sdk` behind the same runtime interface.

Sources:

- Cursor Cloud Agents API docs: https://cursor.com/docs/cloud-agent/api/endpoints
- Cursor SDK launch post: https://cursor.com/blog/typescript-sdk
