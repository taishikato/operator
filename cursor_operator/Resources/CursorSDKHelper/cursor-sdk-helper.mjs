import { pathToFileURL } from "node:url";

if (isMainModule()) {
  const input = await readJSONFromStdin();

  try {
    if (input.action === "start") {
      await startRun(input);
    } else if (input.action === "wait") {
      await waitForRun(input);
    } else {
      throw new Error("Unsupported Cursor SDK helper action.");
    }
    // Exit explicitly once the result has been written. The Cursor cloud SDK
    // keeps a run-event stream open after the run is created, which would
    // otherwise keep this process alive until the run finishes. The Swift
    // runner only reads stdout after the process exits, so a lingering process
    // would block the "start" result until the run completed. Completion is
    // tracked separately through the "wait" action.
    process.exit(0);
  } catch (error) {
    console.error(sanitizeError(error));
    process.exit(1);
  }
}

function isMainModule() {
  return process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
}

async function startRun(request) {
  const Agent = await cursorAgentClass();
  requireString(request.apiKey, "apiKey");
  requireString(request.agentName, "agentName");
  requireString(request.prompt, "prompt");
  requireString(request.repositoryURL, "repositoryURL");
  requireString(request.startingRef, "startingRef");
  requireString(request.model, "model");

  const agent = await Agent.create({
    apiKey: request.apiKey,
    name: request.agentName,
    model: { id: request.model },
    cloud: {
      repos: [{ url: request.repositoryURL, startingRef: request.startingRef }],
      autoCreatePR: Boolean(request.autoCreatePR),
      workOnCurrentBranch: false,
    },
  });

  const run = await agent.send(request.prompt);
  const agentID = agent.agentId ?? run.agentId;
  requireString(agentID, "agentID");
  requireString(run.id, "runID");

  await writeJSON({
    agentID,
    runID: run.id,
    openURL: `https://cursor.com/agents/${agentID}`,
  });
}

async function waitForRun(request) {
  const Agent = await cursorAgentClass();
  requireString(request.apiKey, "apiKey");
  requireString(request.agentID, "agentID");
  requireString(request.runID, "runID");

  const run = await Agent.getRun(request.runID, {
    runtime: "cloud",
    agentId: request.agentID,
    apiKey: request.apiKey,
  });
  const completedRun = await run.wait();
  const status = completedRun.status ?? run.status;
  requireString(status, "status");

  await writeJSON({
    status,
    result: completedRun.result ?? null,
  });
}

async function readJSONFromStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  if (raw.trim().length === 0) {
    throw new Error("Cursor SDK helper requires JSON input.");
  }
  return JSON.parse(raw);
}

function writeJSON(value) {
  // Resolve only once the line has been flushed to stdout so the explicit
  // process.exit(0) in the main module cannot truncate the result.
  return new Promise((resolve, reject) => {
    process.stdout.write(`${JSON.stringify(value)}\n`, (error) => {
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    });
  });
}

async function cursorAgentClass() {
  const module = await import("@cursor/sdk");
  return module.Agent;
}

function requireString(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Cursor SDK helper missing ${name}.`);
  }
}

export function sanitizeError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/crsr_[A-Za-z0-9_-]+/g, "crsr_[redacted]");
}
