"use strict";
(() => {
  // addon/mv-compat.ts
  var manifestVersion = chrome.runtime.getManifest().manifest_version;
  var storage = {};
  async function storageSet(obj) {
    if (manifestVersion === 2) {
      Object.assign(storage, obj);
      return;
    }
    return chrome.storage.local.set(obj);
  }
  async function storageGet(key) {
    if (key === null) {
      if (manifestVersion === 2) {
        return storage;
      }
      return await chrome.storage.local.get(null);
    }
    if (manifestVersion === 2) {
      return storage[key];
    }
    return (await chrome.storage.local.get(key))?.[key];
  }

  // addon/devtools/panel.ts
  var backgroundPageConnection;
  function sendBackgroundMessage(msg) {
    backgroundPageConnection.postMessage(msg);
  }
  function getRowForInstance(instanceId) {
    const rowId = `instance-${instanceId}`;
    if (document.getElementById(rowId) !== null) {
      const td = document.getElementById(rowId).querySelectorAll("td");
      return td;
    } else {
      const template = document.querySelector("#row");
      const table = document.querySelector("tbody");
      const clone = template.content.cloneNode(true);
      const td = clone.querySelectorAll("td");
      table.appendChild(clone);
      table.lastElementChild.id = rowId;
      return td;
    }
  }
  function reconnect() {
    backgroundPageConnection = chrome.runtime.connect({
      name: "devtools-panel"
    });
    sendBackgroundMessage({
      type: "init",
      tabId: chrome.devtools.inspectedWindow.tabId
    });
    backgroundPageConnection.onMessage.addListener(function(message) {
      if (message.type === "report") {
        const td = getRowForInstance(message.instanceId);
        td[0].innerText = `${message.frameId}`;
        td[1].innerText = message.url;
        td[2].innerText = message.state.lifecycle;
        td[3].innerText = message.state.prehideOn ? "yes" : "no";
        td[4].innerText = `${message.state.findCmpAttempts}`;
        td[5].innerText = message.state.detectedCmps.join(", ");
        td[6].innerText = message.state.detectedPopups.join(", ");
      } else if (message.type === "instanceTerminated") {
        document.getElementById(`instance-${message.instanceId}`)?.classList.add("dead");
      }
    });
    backgroundPageConnection.onDisconnect.addListener(() => {
      reconnect();
    });
    return backgroundPageConnection;
  }
  var clearStorageCheckbox = document.querySelector("#clear-storage");
  var clearPanel = () => {
    const tbody = document.querySelector("tbody");
    while (tbody.firstChild) {
      tbody.removeChild(tbody.firstChild);
    }
  };
  document.getElementById("clear").addEventListener("click", clearPanel);
  document.getElementById("reload").addEventListener("click", async () => {
    if (clearStorageCheckbox.checked) {
      const tab = await chrome.tabs.get(chrome.devtools.inspectedWindow.tabId);
      const url = new URL(tab.url);
      await chrome.browsingData.remove(
        {
          origins: [url.origin]
        },
        {
          cookies: true,
          localStorage: true,
          indexedDB: true
        }
      );
    }
    clearPanel();
    chrome.devtools.inspectedWindow.reload({});
  });
  document.getElementById("mode").addEventListener("change", async () => {
    const storedConfig = await storageGet("config");
    let autoAction = document.querySelector("#mode > option:checked").getAttribute("data-autoaction");
    if (autoAction === "null") {
      autoAction = null;
    }
    storedConfig.autoAction = autoAction;
    storageSet({
      config: storedConfig
    });
  });
  document.getElementById("optin").addEventListener("click", () => {
    chrome.tabs.sendMessage(chrome.devtools.inspectedWindow.tabId, {
      type: "optIn"
    });
  });
  document.getElementById("optout").addEventListener("click", () => {
    chrome.tabs.sendMessage(chrome.devtools.inspectedWindow.tabId, {
      type: "optOut"
    });
  });
  function onConfigUpdated(config) {
    const modeOptions = document.querySelectorAll("#mode > option");
    switch (config.autoAction) {
      case "optIn":
        modeOptions[1].selected = true;
        break;
      case "optOut":
        modeOptions[2].selected = true;
        break;
      default:
        modeOptions[0].selected = true;
    }
  }
  chrome.storage.local.onChanged.addListener((changes) => {
    if (changes.config) {
      onConfigUpdated(changes.config.newValue);
    }
  });
  (async () => {
    const config = await storageGet("config");
    onConfigUpdated(config);
  })();
  reconnect();
})();
