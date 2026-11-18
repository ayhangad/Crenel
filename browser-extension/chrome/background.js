import { isAllowedMeetURL } from "./protocol.js";

const OFFSCREEN_DOCUMENT_PATH = "offscreen.html";
let capturedTabId = null;
let pendingStart = null;
let stopping = null;

function checkPending(attempt) {
  if (attempt.cancelled) throw new Error("Capture cancelled.");
}

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

function stopCapture(reason = "user") {
  if (pendingStart) pendingStart.cancelled = true;
  if (stopping) return stopping;
  stopping = (async () => {
    try {
      const response = await chrome.runtime.sendMessage({ type: "stop-capture", reason });
      if (!response?.ok) throw new Error(response?.error ?? "offscreen capture did not stop");
    } catch (error) {
      const contexts = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"] });
      if (contexts.length) throw error;
    }
    capturedTabId = null;
    await setCaptureBadge(false);
  })().finally(() => { stopping = null; });
  return stopping;
}

async function startCapture(tab, attempt) {
  if (!tab?.id || !isAllowedMeetURL(tab.url)) {
    throw new Error("active tab is not a supported Google Meet call URL");
  }

  attempt.tabId = tab.id;
  await ensureOffscreenDocument();
  checkPending(attempt);
  const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tab.id });
  checkPending(attempt);
  const response = await chrome.runtime.sendMessage({
    type: "start-capture",
    streamId,
    tabId: tab.id,
    sessionId: crypto.randomUUID(),
  });
  checkPending(attempt);
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
    if (pendingStart || stopping) {
      sendResponse({ ok: false, error: "Capture is busy." });
      return false;
    }
    const attempt = { tabId: null, cancelled: false };
    pendingStart = attempt;
    (async () => {
      if (await reconcileCapturedTab() !== null) {
        throw new Error("Başka bir Meet sekmesi zaten bağlı.");
      }
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      checkPending(attempt);
      await startCapture(tab, attempt);
      return { ok: true, active: true, tabId: tab.id };
    })()
      .then(sendResponse)
      .catch(async (error) => {
        if (attempt.cancelled || capturedTabId !== null) {
          sendResponse({ ok: false, active: capturedTabId !== null, error: error.message });
          return;
        }
        await chrome.action.setBadgeBackgroundColor({ color: "#C83C3C" });
        await chrome.action.setBadgeText({ text: "!" });
        sendResponse({ ok: false, active: false, error: error.message });
      }).finally(() => { pendingStart = null; });
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
  if ((info.tabId === capturedTabId || info.tabId === pendingStart?.tabId) && (info.status === "stopped" || info.status === "error")) {
    stopCapture(`tab-${info.status}`);
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  if (tabId === capturedTabId || tabId === pendingStart?.tabId) stopCapture("tab-closed");
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status !== "loading" && (!changeInfo.url || isAllowedMeetURL(changeInfo.url))) return;
  (async () => {
    const activeCaptureTabId = pendingStart?.tabId ?? capturedTabId ?? await reconcileCapturedTab();
    if (tabId === activeCaptureTabId) await stopCapture("tab-navigated");
  })();
});

reconcileCapturedTab().catch(() => setCaptureBadge(false));
