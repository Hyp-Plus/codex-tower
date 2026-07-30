import test from "node:test";
import assert from "node:assert/strict";
import { isCompletionCommand } from "../server/completion-command.mjs";

test("recognizes standalone completion commands in Chinese and English", () => {
  assert.equal(isCompletionCommand("验收完成"), true);
  assert.equal(isCompletionCommand("验收通过！"), true);
  assert.equal(isCompletionCommand("task complete"), true);
  assert.equal(isCompletionCommand("MARK TASK COMPLETE"), true);
});

test("does not treat ordinary discussion as task completion", () => {
  assert.equal(isCompletionCommand("这个任务完成了吗？"), false);
  assert.equal(isCompletionCommand("Please complete the task after the review."), false);
  assert.equal(isCompletionCommand("验收完成后告诉我"), false);
});
