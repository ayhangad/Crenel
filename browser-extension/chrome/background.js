import { isAllowedMeetURL } from "./protocol.js";

const OFFSCREEN_DOCUMENT_PATH = "offscreen.html";
let capturedTabId = null;

async function reconcileCapturedTab() {
  const captures = await chrome.tabCapture.getCapturedTabs();
  const active = captures.find((capture) => (
    capture.status === "active" || capture.status === "pending"
  ));
  capturedTabId = active?.tabId ?? null;
  await setCaptureBadge(capturedTabId !== null);
  return capturedTabId;
}

async function ensureOffscreenDocument() {
  const documentURL = chrome.runtime.getURL(OFFSCREEN_DOCUMENT_PATH);
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
    documentUrls: [documentURL],
  });
  if (contexts.length > 0) return;

  await chrome.offscreen.createDocument({
    url: OFFSCREEN_DOCUMENT_PATH,
    reasons: ["USER_MEDIA", "AUDIO_PLAYBACK"],
    justification: "Capture and locally replay only the user-selected Google Meet tab audio.",
  });
}

async function setCaptureBadge(active) {
  await chrome.action.setBadgeBackgroundColor({ color: active ? "#C83C3C" : "#777777" });
  await chrome.action.setBadgeText({ text: active ? "REC" : "" });
}

async function stopCapture(reason = "user") {
  if (capturedTabId === null) return;
  await chrome.runtime.sendMessage({ type: "stop-capture", reason }).catch(() => {});
  capturedTabId = null;
  await setCaptureBadge(false);
}

async function startCapture(tab) {
  if (!tab?.id || !isAllowedMeetURL(tab.url)) {
    throw new Error("active tab is not a supported Google Meet call URL");
  }

  await ensureOffscreenDocument();
  const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
  const response = await chrome.runtime.sendMessage({
    type: "start-capture",
    streamId,
    tabId: tab.id,
    sessionId: crypto.randomUUID(),
  });
  if (!response?.ok) {
    throw new Error(response?.error ?? "offscreen capture did not start");
  }

  capturedTabId = tab.id;
  await setCaptureBadge(true);
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "capture-state") {
    if (message.state !== "capturing") {
      capturedTabId = null;
      setCaptureBadge(false);
    }
    return false;
  }

  if (message?.type === "get-capture-status") {
    reconcileCapturedTab()
      .then((tabId) => sendResponse({ ok: true, active: tabId !== null, tabId }))
      .catch(() => sendResponse({ ok: false, active: false }));
    return true;
  }

  if (message?.type === "start-selected-tab") {
    (async () => {
      if (await reconcileCapturedTab() !== null) {
        throw new Error("Başka bir Meet sekmesi zaten bağlı.");
      }
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      await startCapture(tab);
      return { ok: true, active: true, tabId: tab.id };
    })()
      .then(sendResponse)
      .catch(async (error) => {
        capturedTabId = null;
        await chrome.action.setBadgeBackgroundColor({ color: "#C83C3C" });
        await chrome.action.setBadgeText({ text: "!" });
        sendResponse({ ok: false, active: false, error: error.message });
      });
    return true;
  }

  if (message?.type === "stop-selected-tab") {
    stopCapture("user")
      .then(() => sendResponse({ ok: true, active: false }))
      .catch((error) => sendResponse({ ok: false, active: true, error: error.message }));
    return true;
  }

  return false;
});

chrome.tabCapture.onStatusChanged.addListener((info) => {
  if (info.tabId === capturedTabId && (info.status === "stopped" || info.status === "error")) {
    stopCapture(`tab-${info.status}`);
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === capturedTabId) stopCapture("tab-closed");
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (!changeInfo.url) return;
  (async () => {
    const activeCaptureTabId = capturedTabId ?? await reconcileCapturedTab();
    if (tabId === activeCaptureTabId) await stopCapture("tab-navigated");
  })();
});

reconcileCapturedTab().catch(() => setCaptureBadge(false));
