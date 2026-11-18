import {
  NATIVE_HOST_NAME,
  PCMProtocolSession,
  PROTOCOL_VERSION,
} from "./protocol.js";

let activeCapture = null;
let pendingCapture = null;
let stopping = null;

function waitForNativeReady(port, sessionId, capture) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timeout);
      capture.cancelReady = null;
      port.onMessage.removeListener(listener);
      port.onDisconnect.removeListener(disconnected);
    };
    const listener = (message) => {
      if (message?.type === "error") {
        cleanup();
        reject(new Error(message.error ?? "native bridge rejected capture"));
      } else if (message?.type === "ready" && message.sessionId === sessionId) {
        cleanup();
        resolve();
      }
    };
    const disconnected = () => {
      cleanup();
      reject(new Error("native bridge disconnected before ready"));
    };
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("native bridge ready timeout"));
    }, 2_000);
    capture.cancelReady = () => { cleanup(); reject(new Error("Capture cancelled.")); };
    port.onMessage.addListener(listener);
    port.onDisconnect.addListener(disconnected);
  });
}

async function dispose(capture, reason) {
  if (capture.worklet) capture.worklet.port.onmessage = null;
  capture.stream?.getTracks().forEach((track) => track.stop());
  if (capture.nativePort) {
    try {
      capture.nativePort.postMessage({
        version: PROTOCOL_VERSION,
        type: "stop",
        sessionId: capture.sessionId,
        reason,
      });
    } catch { /* Port already disconnected. */ }
    try { capture.nativePort.disconnect(); } catch { /* Port already disconnected. */ }
  }
  if (capture.audioContext) await capture.audioContext.close().catch(() => {});
}

function stopCapture(reason = "user") {
  if (stopping) return stopping;
  const pending = pendingCapture;
  if (pending) {
    pending.cancelled = true;
    pending.cancelReady?.();
  }
  const capture = activeCapture;
  activeCapture = null;
  stopping = (async () => {
    if (pending) await pending.finished;
    if (capture) await dispose(capture, reason);
    await chrome.runtime.sendMessage({ type: "capture-state", state: "stopped", reason });
  })().finally(() => { stopping = null; });
  return stopping;
}

async function startCapture(message) {
  if (activeCapture || pendingCapture || stopping) throw new Error("capture is already busy");
  if (typeof message.streamId !== "string" || typeof message.sessionId !== "string") {
    throw new Error("invalid capture request");
  }
  let finish;
  const capture = {
    sessionId: message.sessionId,
    cancelled: false,
    finished: new Promise((resolve) => { finish = resolve; }),
  };
  pendingCapture = capture;
  function checkCancelled() {
    if (capture.cancelled) throw new Error("Capture cancelled.");
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { mandatory: { chromeMediaSource: "tab", chromeMediaSourceId: message.streamId } },
      video: false,
    });
    capture.stream = stream;
    checkCancelled();
    const nativePort = chrome.runtime.connectNative(NATIVE_HOST_NAME);
    capture.nativePort = nativePort;
    const protocol = new PCMProtocolSession(message.sessionId);
    nativePort.postMessage({
      version: PROTOCOL_VERSION,
      type: "start",
      sessionId: message.sessionId,
      client: "googleMeetChrome",
      tabId: message.tabId,
    });
    await waitForNativeReady(nativePort, message.sessionId, capture);
    checkCancelled();

    const audioContext = new AudioContext({ sampleRate: 48_000 });
    capture.audioContext = audioContext;
    await Promise.race([
      audioContext.audioWorklet.addModule("pcm-worklet.js"),
      new Promise((_, reject) => {
        capture.cancelReady = () => reject(new Error("Capture cancelled."));
      }),
    ]);
    capture.cancelReady = null;
    checkCancelled();
    const source = audioContext.createMediaStreamSource(stream);
    const worklet = new AudioWorkletNode(audioContext, "crenel-pcm-chunker");
    const silentOutput = audioContext.createGain();
    silentOutput.gain.value = 0;

    source.connect(audioContext.destination);
    source.connect(worklet).connect(silentOutput).connect(audioContext.destination);

    capture.worklet = worklet;
    activeCapture = capture;
    const stopIfCurrent = (reason) => {
      if (activeCapture === capture) stopCapture(reason);
    };
    nativePort.onMessage.addListener((nativeMessage) => {
      if (nativeMessage?.type !== "ack" || nativeMessage.sessionId !== protocol.sessionId) return;
      try {
        protocol.acknowledge(nativeMessage.sequence);
      } catch {
        stopIfCurrent("invalid-native-ack");
      }
    });
    nativePort.onDisconnect.addListener(() => stopIfCurrent("native-bridge-disconnected"));
    stream.getAudioTracks()[0].addEventListener("ended", () => stopIfCurrent("tab-stream-ended"));
    worklet.port.onmessage = ({ data }) => {
      if (activeCapture !== capture || !(data?.samples instanceof Float32Array)) return;
      try {
        nativePort.postMessage(protocol.makeAudioMessage(
          data.samples,
          data.sampleRate,
          data.channels,
        ));
      } catch {
        stopIfCurrent("native-backpressure-or-pcm-error");
      }
    };
    chrome.runtime.sendMessage({ type: "capture-state", state: "capturing" });
  } catch (error) {
    if (activeCapture === capture) activeCapture = null;
    await dispose(capture, "start-interrupted");
    throw error;
  } finally {
    pendingCapture = null;
    finish();
  }
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "start-capture") {
    startCapture(message)
      .then(() => sendResponse({ ok: true }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "stop-capture") {
    stopCapture(message.reason)
      .then(() => sendResponse({ ok: true }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  return false;
});
