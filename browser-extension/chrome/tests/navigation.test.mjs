import assert from "node:assert/strict";
import test from "node:test";

test("loading without a visible URL stops only the captured Meet tab", async () => {
  let onUpdated;
  const sent = [];
  const noop = () => {};
  globalThis.chrome = {
    runtime: {
      onMessage: { addListener: noop },
      sendMessage: async (message) => { sent.push(message); return { ok: true }; },
    },
    action: { setBadgeBackgroundColor: noop, setBadgeText: noop },
    tabCapture: {
      onStatusChanged: { addListener: noop },
      getCapturedTabs: async () => [{ tabId: 9, status: "active" }],
    },
    tabs: {
      onRemoved: { addListener: noop },
      onUpdated: { addListener: (callback) => { onUpdated = callback; } },
    },
  };
  try {
    await import("../background.js");
    const settle = () => new Promise((resolve) => setImmediate(resolve));
    await settle();
    onUpdated(8, { status: "loading" });
    onUpdated(9, { status: "complete" });
    await settle();
    assert.deepEqual(sent, []);
    onUpdated(9, { status: "loading" });
    await settle();
    assert.deepEqual(sent, [{ type: "stop-capture", reason: "tab-navigated" }]);
  } finally {
    delete globalThis.chrome;
  }
});
