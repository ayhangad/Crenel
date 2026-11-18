import assert from "node:assert/strict";
import test from "node:test";

function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { resolve, promise };
}

for (const stage of ["media", "native ready", "worklet"]) {
  test(`stopping during ${stage} acknowledges after releasing every acquired resource`, async () => {
    let listener;
    const calls = [];
    const media = deferred();
    const waiting = deferred();
    let ready;
    const sessionId = "12345678-1234-1234-1234-123456789abc";
    const stream = { getTracks: () => [{ stop: () => calls.push("track stopped") }] };
    const nativePort = {
      onDisconnect: { addListener() {}, removeListener() {} },
      onMessage: { addListener(fn) { ready = fn; waiting.resolve(); }, removeListener() {} },
      postMessage(message) { calls.push(message.type); },
      disconnect() { calls.push("port closed"); },
    };
    globalThis.chrome = { runtime: {
      onMessage: { addListener(fn) { listener = fn; } },
      connectNative: () => nativePort,
      sendMessage: async ({ state }) => { calls.push(state); },
    } };
    const original = Object.getOwnPropertyDescriptor(globalThis, "navigator");
    Object.defineProperty(globalThis, "navigator", {
      configurable: true, value: { mediaDevices: { getUserMedia: () => media.promise } },
    });
    const loading = deferred();
    globalThis.AudioContext = class {
      audioWorklet = { addModule: () => { loading.resolve(); return new Promise(() => {}); } };
      close() { calls.push("context closed"); return Promise.resolve(); }
    };
    try {
      await import(`../offscreen.js?stage=${encodeURIComponent(stage)}`);
      const call = (message) => new Promise((resolve) => listener(message, {}, resolve));
      const start = call({ type: "start-capture", tabId: 3, streamId: "test", sessionId });
      if (stage !== "media") {
        media.resolve(stream);
        await waiting.promise;
      }
      if (stage === "worklet") {
        ready({ type: "ready", sessionId });
        await loading.promise;
      }
      const stop = call({ type: "stop-capture", reason: "user" });
      media.resolve(stream);
      assert.deepEqual(await stop, { ok: true });
      assert.equal((await start).ok, false);
      assert.ok(calls.indexOf("track stopped") < calls.indexOf("stopped"));
      assert.equal(calls.filter((call) => call === "track stopped").length, 1);
      assert.equal(calls.includes("port closed"), stage !== "media");
      assert.equal(calls.includes("context closed"), stage === "worklet");
      assert.equal(calls.includes("capturing"), false);
    } finally {
      if (original) Object.defineProperty(globalThis, "navigator", original);
      else delete globalThis.navigator;
      delete globalThis.chrome;
      delete globalThis.AudioContext;
    }
  });
}
