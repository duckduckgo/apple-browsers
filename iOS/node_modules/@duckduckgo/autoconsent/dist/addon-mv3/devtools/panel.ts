import { BackgroundDevtoolsMessage, DevtoolsMessage } from '../../lib/messages';
import { Config } from '../../lib/types';
import { storageGet, storageSet } from '../mv-compat';

let backgroundPageConnection: chrome.runtime.Port;

function sendBackgroundMessage(msg: DevtoolsMessage) {
    backgroundPageConnection.postMessage(msg);
}

function getRowForInstance(instanceId: string) {
    const rowId = `instance-${instanceId}`;
    if (document.getElementById(rowId) !== null) {
        // update existing row
        const td = document.getElementById(rowId).querySelectorAll('td');
        return td;
    } else {
        const template: HTMLTemplateElement = document.querySelector('#row');
        const table = document.querySelector('tbody');
        const clone = template.content.cloneNode(true) as HTMLElement;
        const td = clone.querySelectorAll('td');
        table.appendChild(clone);
        table.lastElementChild.id = rowId;
        return td;
    }
}

function reconnect(): chrome.runtime.Port {
    backgroundPageConnection = chrome.runtime.connect({
        name: 'devtools-panel',
    });
    sendBackgroundMessage({
        type: 'init',
        tabId: chrome.devtools.inspectedWindow.tabId,
    });

    backgroundPageConnection.onMessage.addListener(function (message: BackgroundDevtoolsMessage) {
        if (message.type === 'report') {
            const td = getRowForInstance(message.instanceId);
            td[0].innerText = `${message.frameId}`;
            td[1].innerText = message.url;
            td[2].innerText = message.state.lifecycle;
            td[3].innerText = message.state.prehideOn ? 'yes' : 'no';
            td[4].innerText = `${message.state.findCmpAttempts}`;
            td[5].innerText = message.state.detectedCmps.join(', ');
            td[6].innerText = message.state.detectedPopups.join(', ');
        } else if (message.type === 'instanceTerminated') {
            document.getElementById(`instance-${message.instanceId}`)?.classList.add('dead');
        }
    });

    backgroundPageConnection.onDisconnect.addListener(() => {
        reconnect();
    });

    return backgroundPageConnection;
}

const clearStorageCheckbox: HTMLInputElement = document.querySelector('#clear-storage');

const clearPanel = () => {
    const tbody = document.querySelector('tbody');
    while (tbody.firstChild) {
        tbody.removeChild(tbody.firstChild);
    }
};
document.getElementById('clear').addEventListener('click', clearPanel);

document.getElementById('reload').addEventListener('click', async () => {
    if (clearStorageCheckbox.checked) {
        const tab = await chrome.tabs.get(chrome.devtools.inspectedWindow.tabId);
        const url = new URL(tab.url);
        await chrome.browsingData.remove(
            {
                origins: [url.origin],
            },
            {
                cookies: true,
                localStorage: true,
                indexedDB: true,
            },
        );
    }
    clearPanel();
    chrome.devtools.inspectedWindow.reload({});
});

document.getElementById('mode').addEventListener('change', async () => {
    const storedConfig = await storageGet('config');
    let autoAction = document.querySelector('#mode > option:checked').getAttribute('data-autoaction');
    if (autoAction === 'null') {
        autoAction = null;
    }
    storedConfig.autoAction = autoAction;
    storageSet({
        config: storedConfig,
    });
});

document.getElementById('optin').addEventListener('click', () => {
    chrome.tabs.sendMessage(chrome.devtools.inspectedWindow.tabId, {
        type: 'optIn',
    });
});

document.getElementById('optout').addEventListener('click', () => {
    chrome.tabs.sendMessage(chrome.devtools.inspectedWindow.tabId, {
        type: 'optOut',
    });
});

function onConfigUpdated(config: Config) {
    const modeOptions: NodeListOf<HTMLOptionElement> = document.querySelectorAll('#mode > option');
    switch (config.autoAction) {
        case 'optIn':
            modeOptions[1].selected = true;
            break;
        case 'optOut':
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
    const config = await storageGet('config');
    onConfigUpdated(config);
})();

reconnect();
