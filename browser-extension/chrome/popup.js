const captureButton = document.querySelector("#capture-button");
const captureButtonIcon = document.querySelector("#capture-button-icon");
const captureButtonLabel = document.querySelector("#capture-button-label");
const status = document.querySelector("#status");
const error = document.querySelector("#error");

let isActive = false;

function render(state) {
  isActive = state.active === true;
  document.body.dataset.state = isActive ? "active" : "idle";
  status.textContent = isActive ? "Meet sekmesi bağlı" : "Bağlantı kapalı";
  captureButtonLabel.textContent = isActive ? "Bağlantıyı kes" : "Meet sekmesini bağla";
  captureButtonIcon.src = isActive ? "images/figma-stop.svg" : "images/figma-video.svg";
  captureButton.disabled = false;
  error.hidden = true;
}

async function refresh() {
  const response = await chrome.runtime.sendMessage({ type: "get-capture-status" });
  if (!response?.ok) throw new Error("Crenel bağlantı durumu okunamadı.");
  render(response);
}

captureButton.addEventListener("click", async () => {
  captureButton.disabled = true;
  error.hidden = true;
  try {
    const response = await chrome.runtime.sendMessage({
      type: isActive ? "stop-selected-tab" : "start-selected-tab",
    });
    if (!response?.ok) throw new Error(response?.error ?? "Bağlantı kurulamadı.");
    render(response);
  } catch (caught) {
    error.textContent = caught.message;
    error.hidden = false;
    captureButton.disabled = false;
  }
});

refresh().catch((caught) => {
  status.textContent = "Bağlantı kullanılamıyor";
  error.textContent = caught.message;
  error.hidden = false;
  captureButton.disabled = false;
});
