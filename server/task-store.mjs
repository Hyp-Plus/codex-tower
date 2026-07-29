import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";

// The menu-bar app and plugin deliberately share this user-local directory.
// CODEX_TOWER_DATA_DIR is useful for tests and advanced custom installations.
export const dataRoot = process.env.CODEX_TOWER_DATA_DIR || path.join(homedir(), "Library", "Application Support", "Codex Tower");
const tasksDir = path.join(dataRoot, "tasks");
const settingsPath = path.join(dataRoot, "settings.json");
const defaultSettings = { muted: false, sounds: { attention: "Glass", complete: "Hero", blocked: "Basso" } };

const now = () => new Date().toISOString();
const taskPath = (sessionId) => path.join(tasksDir, `${encodeURIComponent(sessionId)}.json`);
const safely = async (fn, fallback) => { try { return await fn(); } catch (error) { if (error.code === "ENOENT") return fallback; throw error; } };

async function writeJson(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
  await rename(temporary, filePath);
}

export async function getSettings() {
  return { ...defaultSettings, ...(await safely(async () => JSON.parse(await readFile(settingsPath, "utf8")), {})) };
}

export async function setSettings(patch) {
  const current = await getSettings();
  const next = { ...current, ...patch, sounds: { ...current.sounds, ...(patch.sounds || {}) } };
  await writeJson(settingsPath, next);
  return next;
}

export async function getTask(sessionId) {
  return safely(async () => JSON.parse(await readFile(taskPath(sessionId), "utf8")), null);
}

export async function saveTask(task) {
  await writeJson(taskPath(task.sessionId), task);
  return task;
}

export async function updateTask(sessionId, changes) {
  const existing = await getTask(sessionId);
  const task = {
    sessionId,
    title: `Codex task ${sessionId.slice(0, 8)}`,
    status: "running",
    createdAt: now(),
    updatedAt: now(),
    completedSteps: 0,
    totalSteps: 0,
    subagents: {},
    ...existing,
    ...changes,
    updatedAt: changes.updatedAt || now()
  };
  return saveTask(task);
}

export async function listTasks() {
  const { readdir } = await import("node:fs/promises");
  const entries = await safely(() => readdir(tasksDir, { withFileTypes: true }), []);
  const tasks = await Promise.all(entries.filter((entry) => entry.isFile() && entry.name.endsWith(".json")).map(async (entry) => JSON.parse(await readFile(path.join(tasksDir, entry.name), "utf8"))));
  return tasks.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
}

export async function clearData() {
  await rm(dataRoot, { recursive: true, force: true });
}
