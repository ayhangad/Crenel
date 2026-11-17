import {
  NATIVE_HOST_NAME,
  PCMProtocolSession,
  PROTOCOL_VERSION,
} from "./protocol.js";

let activeCapture = null;

function waitForNativeReady(port, sessionId) {
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timeout);
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
    port.onMessage.addListener(listener);
    port.onDisconnect.addListener(disconnected);
  });
}

async function stopCapture(reason = "user") {
  const capture = activeCapture;
  activeCapture = null;
  if (!capture) return;

  capture.worklet.port.onmessage = null;
  capture.stream.getTracks().forEach((track) => track.stop());
  try {
    capture.nativePort.postMessage({
      version: PROTOCOL_VERSION,
      type: "stop",
      sessionId: capture.protocol.sessionId,
      reason,
    });
  } catch {
    // The application bridge already fails closed when the native port disappears.
  }
  try {
    capture.nativePort.disconnect();
  } catch {
    // Port may already be disconnected; local media cleanup must still finish.
  }
  await capture.audioContext.close().catch(() => {});
  chrome.runtime.sendMessage({ type: "capture-state", state: "stopped", reason });
}

async function startCapture(message) {
  if (activeCapture) throw new Error("capture is already active");
  if (typeof message.streamId !== "string" || typeof message.sessionId !== "string") {
    throw new Error("invalid capture request");
  }

  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      mandatory: {
        chromeMediaSource: "tab",
        chromeMediaSourceId: message.streamId,
      },
    },
    video: false,
  });
  const nativePort = chrome.runtime.connectNative(NATIVE_HOST_NAME);
  const protocol = new PCMProtocolSession(message.sessionId);

  try {
    nativePort.postMessage({
      version: PROTOCOL_VERSION,
      type: "start",
      sessionId: message.sessionId,
      client: "googleMeetChrome",
      tabId: message.tabId,
    });
    await waitForNativeReady(nativePort, message.sessionId);

    const audioContext = new AudioContext({ sampleRate: 48_000 });
    await audioContext.audioWorklet.addModule("pcm-worklet.js");
    const source = audioContext.createMediaStreamSource(stream);
    const worklet = new AudioWorkletNode(audioContext, "crenel-pcm-chunker");
    const silentOutput = audioContext.createGain();
    silentOutput.gain.value = 0;

    source.connect(audioContext.destination);
    source.connect(worklet).connect(silentOutput).connect(audioContext.destination);

    activeCapture = { audioContext, nativePort, protocol, stream, worklet };
    nativePort.onMessage.addListener((nativeMessage) => {
      if (nativeMessage?.type !== "ack" || nativeMessage.sessionId !== protocol.sessionId) return;
      try {
        protocol.acknowledge(nativeMessage.sequence);
      } catch {
        stopCapture("invalid-native-ack");
      }
    });
    nativePort.onDisconnect.addListener(() => stopCapture("native-bridge-disconnected"));
    stream.getAudioTracks()[0].addEventListener("ended", () => stopCapture("tab-stream-ended"));
    worklet.port.onmessage = ({ data }) => {
      if (!activeCapture || !(data?.samples instanceof Float32Array)) return;
      try {
        nativePort.postMessage(protocol.makeAudioMessage(
          data.samples,
          data.sampleRate,
          data.channels,
        ));
      } catch {
        stopCapture("native-backpressure-or-pcm-error");
      }
    };
    chrome.runtime.sendMessage({ type: "capture-state", state: "capturing" });
  } catch (error) {
    stream.getTracks().forEach((track) => track.stop());
    nativePort.disconnect();
    throw error;
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
    stopCapture(message.reason).then(() => sendResponse({ ok: true }));
    return true;
  }
  return false;
});
