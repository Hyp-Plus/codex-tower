import { spawn } from "node:child_process";
import { getSettings, updateTask } from "../server/task-store.mjs";

const input = await new Promise((resolve, reject) => {
  let body = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk) => { body += chunk; });
  process.stdin.on("end", () => { try { resolve(body ? JSON.parse(body) : {}); } catch (error) { reject(error); } });
  process.stdin.on("error", reject);
});

const event = input.hook_event_name || input.hookEventName;
const sessionId = input.session_id || input.sessionId;
if (!sessionId || !event) process.exit(0);

function titleFromPrompt(prompt) {
  const compact = String(prompt || "").replace(/\s+/g, " ").trim();
  return compact ? compact.slice(0, 100) : undefined;
}

function play(sound) {
  if (process.platform !== "darwin") return;
  const file = `/System/Library/Sounds/${sound}.aiff`;
  const child = spawn("/usr/bin/afplay", [file], { detached: true, stdio: "ignore" });
  child.unref();
}

const task = await (async () => {
  switch (event) {
    case "SessionStart":
      return updateTask(sessionId, { source: "live", status: "ready", cwd: input.cwd || null, model: input.model || null, closedAt: null });
    case "UserPromptSubmit":
      return updateTask(sessionId, { source: "live", status: "running", title: titleFromPrompt(input.prompt), turnId: input.turn_id || input.turnId || null, waitingReason: null, completedAt: null });
    case "PermissionRequest":
      return updateTask(sessionId, { status: "waiting_for_you", waitingReason: input.tool_input?.description || `Approval needed for ${input.tool_name || "a tool"}` });
    case "PostToolUse": {
      const steps = input.tool_input?.plan || input.tool_input?.steps || [];
      const completedSteps = Array.isArray(steps) ? steps.filter((step) => step.status === "completed").length : 0;
      return updateTask(sessionId, { completedSteps, totalSteps: Array.isArray(steps) ? steps.length : 0 });
    }
    case "Stop":
      return updateTask(sessionId, { status: "awaiting_review", waitingReason: null, stoppedAt: new Date().toISOString() });
    case "SessionEnd":
      return updateTask(sessionId, { status: "closed", closedAt: new Date().toISOString() });
    case "SubagentStart":
    case "SubagentStop": {
      const previous = (await updateTask(sessionId, {})).subagents || {};
      const agentId = input.agent_id || input.agentId || "unknown";
      return updateTask(sessionId, { subagents: { ...previous, [agentId]: { type: input.agent_type || input.agentType || "default", status: event === "SubagentStart" ? "running" : "stopped", updatedAt: new Date().toISOString() } } });
    }
    default:
      return updateTask(sessionId, {});
  }
})();

const settings = await getSettings();
if (!settings.muted && event === "PermissionRequest") play(settings.sounds.blocked);
if (!settings.muted && event === "Stop" && task.status === "awaiting_review") play(settings.sounds.attention);
process.exit(0);
