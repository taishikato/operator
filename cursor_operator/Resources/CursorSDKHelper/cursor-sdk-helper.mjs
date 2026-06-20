import { Agent } from "@cursor/sdk";

const input = await readJSONFromStdin();

try {
  if (input.action === "start") {
    await startRun(input);
  } else if (input.action === "wait") {
    await waitForRun(input);
  } else {
    throw new Error("Unsupported Cursor SDK helper action.");
  }
} catch (error) {
  console.error(sanitizeError(error));
  process.exit(1);
}

async function startRun(request) {
  requireString(request.apiKey, "apiKey");
  requireString(request.prompt, "prompt");
  requireString(request.repositoryURL, "repositoryURL");
  requireString(request.startingRef, "startingRef");
  requireString(request.model, "model");

  const agent = await Agent.create({
    apiKey: request.apiKey,
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

  writeJSON({
    agentID,
    runID: run.id,
    openURL: `https://cursor.com/agents/${agentID}`,
  });
}

async function waitForRun(request) {
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

  writeJSON({
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
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

function requireString(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Cursor SDK helper missing ${name}.`);
  }
}

function sanitizeError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/crsr_[A-Za-z0-9_-]+/g, "crsr_[redacted]");
}
