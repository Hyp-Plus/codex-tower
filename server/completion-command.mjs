const completionCommands = new Set([
  "验收完成",
  "验收通过",
  "任务完成",
  "task complete",
  "complete task",
  "mark task complete"
]);

function normalize(prompt) {
  return String(prompt || "")
    .trim()
    .toLowerCase()
    .replace(/[。！!]+$/u, "");
}

export function isCompletionCommand(prompt) {
  return completionCommands.has(normalize(prompt));
}
