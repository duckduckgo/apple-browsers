// Pulls the live search token from the app and maintains a dynamic modifyHeaders
// session rule that tags SERP navigations with x-temp-tablet. Refreshed on startup
// and whenever the app wakes us via the "refresh-token" command (on token fetch).
const api = globalThis.browser || globalThis.chrome;
const APP_ID = "com.duckduckgo.web-extension.search-token";
const RULE_ID = 1;

async function pullAndSet() {
    let token;
    try {
        const reply = await api.runtime.sendNativeMessage(APP_ID, { featureName: "searchToken", method: "getToken" });
        token = reply && reply.result ? reply.result.token : undefined;
    } catch (e) {
        console.log("[search-token] getToken failed: " + String(e));
        return;
    }
    if (token) {
        await api.declarativeNetRequest.updateSessionRules({
            removeRuleIds: [RULE_ID],
            addRules: [{
                id: RULE_ID,
                priority: 1,
                action: { type: "modifyHeaders", requestHeaders: [{ header: "x-temp-tablet", operation: "set", value: token }] },
                condition: { urlFilter: "||duckduckgo.com/", resourceTypes: ["main_frame"] }
            }]
        });
    } else {
        // No valid token — never tag with a stale/absent one.
        await api.declarativeNetRequest.updateSessionRules({ removeRuleIds: [RULE_ID] });
    }
}

api.commands.onCommand.addListener((command) => {
    if (command === "refresh-token") { pullAndSet(); }
});

pullAndSet();
