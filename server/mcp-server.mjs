import { spawn } from "node:child_process";
import { getSettings, getTask, listTasks, setSettings, updateTask } from "./task-store.mjs";
import { syncExistingTasks } from "./sync-existing.mjs";

const tools = [
  { name: "list_tasks", description: "List locally tracked Codex Tower tasks without chat contents.", inputSchema: { type: "object", properties: { status: { type: "string", description: "Optional status filter." } } } },
  { name: "get_task", description: "Read one locally tracked Codex Tower task by session ID.", inputSchema: { type: "object", properties: { session_id: { type: "string" } }, required: ["session_id"] } },
  { name: "mark_task_complete", description: "Explicitly mark a verified Codex task complete and play the completion sound once.", inputSchema: { type: "object", properties: { session_id: { type: "string" }, summary: { type: "string", description: "Optional brief completion note; never include secrets." } }, required: ["session_id"] } },
  { name: "sync_existing_tasks", description: "Import existing local Codex threads into Codex Tower as history without reading or saving their transcript contents.", inputSchema: { type: "object", properties: {} } },
  { name: "update_settings", description: "Change Codex Tower local notification settings.", inputSchema: { type: "object", properties: { muted: { type: "boolean" } } } }
];

function result(value) { return { content: [{ type: "text", text: JSON.stringify(value, null, 2) }], structuredContent: value }; }
function play(sound) { if (process.platform === "darwin") { const child = spawn("/usr/bin/afplay", [`/System/Library/Sounds/${sound}.aiff`], { detached: true, stdio: "ignore" }); child.unref(); } }

async function call(name, args) {
  if (name === "list_tasks") { const tasks = await listTasks(); return { tasks: args.status ? tasks.filter((task) => task.status === args.status) : tasks }; }
  if (name === "get_task") return { task: await getTask(args.session_id) };
  if (name === "update_settings") return { settings: await setSettings(args) };
  if (name === "sync_existing_tasks") return await syncExistingTasks();
  if (name === "mark_task_complete") {
    const existing = await getTask(args.session_id);
    if (!existing) throw new Error(`No Codex Tower task exists for session ${args.session_id}.`);
    const wasComplete = existing.status === "completed";
    const task = await updateTask(args.session_id, { status: "completed", completedAt: existing.completedAt || new Date().toISOString(), completionSummary: args.summary || existing.completionSummary || null, waitingReason: null });
    const settings = await getSettings();
    if (!wasComplete && !settings.muted) play(settings.sounds.complete);
    return { task, completionSoundPlayed: !wasComplete && !settings.muted };
  }
  throw new Error(`Unknown tool: ${name}`);
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", async (chunk) => {
  buffer += chunk;
  const lines = buffer.split("\n");
  buffer = lines.pop();
  for (const line of lines) {
    if (!line.trim()) continue;
    const request = JSON.parse(line);
    let response;
    try {
      if (request.method === "initialize") response = { jsonrpc: "2.0", id: request.id, result: { protocolVersion: request.params?.protocolVersion || "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "codex-tower", version: "0.1.0" } } };
      else if (request.method === "tools/list") response = { jsonrpc: "2.0", id: request.id, result: { tools } };
      else if (request.method === "tools/call") response = { jsonrpc: "2.0", id: request.id, result: result(await call(request.params.name, request.params.arguments || {})) };
      else if (request.id !== undefined) response = { jsonrpc: "2.0", id: request.id, error: { code: -32601, message: `Method not found: ${request.method}` } };
    } catch (error) { response = { jsonrpc: "2.0", id: request.id, error: { code: -32000, message: error.message } }; }
    if (response) process.stdout.write(`${JSON.stringify(response)}\n`);
  }
});
