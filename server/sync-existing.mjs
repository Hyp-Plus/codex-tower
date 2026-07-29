import { existsSync } from "node:fs";
import { spawn } from "node:child_process";
import { getTask, updateTask } from "./task-store.mjs";

const codexCommand = existsSync("/Applications/ChatGPT.app/Contents/Resources/codex")
  ? "/Applications/ChatGPT.app/Contents/Resources/codex"
  : "codex";

const isoFromEpochSeconds = (seconds) => typeof seconds === "number" ? new Date(seconds * 1000).toISOString() : new Date().toISOString();
const titleFor = (thread) => {
  const title = String(thread.name || "").replace(/\s+/g, " ").trim();
  return title ? title.slice(0, 100) : `Codex task ${thread.id.slice(0, 8)}`;
};

function listThreads(archived) {
  return new Promise((resolve, reject) => {
    const child = spawn(codexCommand, ["app-server", "--stdio"], { stdio: ["pipe", "pipe", "pipe"] });
    let buffer = "";
    const threads = [];
    let requestId = 0;
    const timeout = setTimeout(() => {
      child.kill();
      reject(new Error("Timed out while listing Codex threads."));
    }, 30_000);
    const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);
    const listPage = (cursor = null) => send({
      method: "thread/list",
      id: ++requestId,
      params: {
        cursor,
        limit: 100,
        sortKey: "updated_at",
        archived,
        sourceKinds: ["cli", "vscode", "appServer", "exec", "unknown"]
      }
    });

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      buffer += chunk;
      const lines = buffer.split("\n");
      buffer = lines.pop();
      for (const line of lines) {
        if (!line.trim()) continue;
        const message = JSON.parse(line);
        if (message.id === 0) {
          send({ method: "initialized", params: {} });
          listPage();
        } else if (message.id && message.result?.data) {
          threads.push(...message.result.data);
          if (message.result.nextCursor) listPage(message.result.nextCursor);
          else {
            clearTimeout(timeout);
            child.kill();
            resolve(threads);
          }
        } else if (message.id && message.error) {
          clearTimeout(timeout);
          child.kill();
          reject(new Error(message.error.message || "Codex App Server rejected thread/list."));
        }
      }
    });
    child.stderr.on("data", () => {});
    child.on("error", reject);
    send({ method: "initialize", id: 0, params: { clientInfo: { name: "codex_tower", title: "Codex Tower", version: "0.1.1" } } });
  });
}

export async function syncExistingTasks() {
  const [activeThreads, archivedThreads] = await Promise.all([listThreads(false), listThreads(true)]);
  const threads = [
    ...activeThreads.map((thread) => ({ ...thread, archived: false })),
    ...archivedThreads.map((thread) => ({ ...thread, archived: true }))
  ];
  let imported = 0;
  let preserved = 0;
  for (const thread of threads) {
    const existing = await getTask(thread.id);
    if (existing && existing.source !== "imported") {
      preserved += 1;
      continue;
    }
    await updateTask(thread.id, {
      source: "imported",
      title: titleFor(thread),
      status: "history",
      createdAt: isoFromEpochSeconds(thread.createdAt),
      importedAt: new Date().toISOString(),
      updatedAt: isoFromEpochSeconds(thread.updatedAt),
      cwd: thread.cwd || null,
      model: thread.modelProvider || null,
      completedSteps: 0,
      totalSteps: 0,
      waitingReason: null,
      subagents: {},
      archived: Boolean(thread.archived)
    });
    imported += 1;
  }
  return { discovered: threads.length, imported, preserved };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  syncExistingTasks().then((result) => console.log(JSON.stringify(result))).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
