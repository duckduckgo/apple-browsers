const optionalPermissions = ["nativeMessaging", "tabs"];

const resultSection = document.getElementById("result");
const resultLabel = document.getElementById("result-label");
const resultDetail = document.getElementById("result-detail");
const grantedList = document.getElementById("granted");

function showResult(kind, label, detail) {
  resultSection.hidden = false;
  resultSection.className = kind;
  resultLabel.textContent = label;
  resultDetail.textContent = detail;
}

async function refreshGranted() {
  const { permissions = [] } = await chrome.permissions.getAll();
  grantedList.replaceChildren(...optionalPermissions.map((permission) => {
    const item = document.createElement("li");
    const isGranted = permissions.includes(permission);
    item.className = isGranted ? "on" : "off";
    item.textContent = permission;
    item.title = isGranted ? "Granted" : "Not granted";
    return item;
  }));
}

for (const button of document.querySelectorAll("button.action")) {
  button.addEventListener("click", async () => {
    const permissions = button.dataset.permissions.split(",");
    try {
      const granted = await chrome.permissions.request({ permissions });
      const { permissions: all = [] } = await chrome.permissions.getAll();
      const now = permissions.filter((permission) => all.includes(permission));
      showResult(
        granted ? "granted" : "denied",
        granted ? "Granted" : "Not granted",
        now.length ? `Has: ${now.join(", ")}` : "Has none of the requested permissions"
      );
    } catch (error) {
      showResult("error", "Error", String(error.message ?? error));
    }
    await refreshGranted();
  });
}

document.getElementById("reset").addEventListener("click", async () => {
  try {
    await chrome.permissions.remove({ permissions: optionalPermissions });
    showResult("neutral", "Removed", "Request again to see the prompts");
  } catch (error) {
    showResult("error", "Error", String(error.message ?? error));
  }
  await refreshGranted();
});

refreshGranted();
