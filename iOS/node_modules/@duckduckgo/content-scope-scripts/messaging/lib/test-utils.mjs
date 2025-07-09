/**
 * @typedef {import("../../messaging/lib/windows.js").WindowsRequestMessage} WindowsRequestMessage
 * @typedef {import("../../messaging/lib/windows.js").WindowsNotification} WindowsNotification
 * @typedef {import("../../messaging/index.js").SubscriptionEvent} SubscriptionEvent
 * @typedef {import("../../messaging/index.js").MessageResponse} MessageResponse
 * @typedef {import("../../messaging/index.js").RequestMessage} RequestMessage
 * @typedef {import("../../messaging/index.js").NotificationMessage} NotificationMessage
 * @typedef {WindowsRequestMessage | WindowsNotification | SubscriptionEvent} AnyWindowsMessage
 * @typedef {import("../../injected/integration-test/type-helpers.mjs").PlatformInfo} PlatformInfo
 */
/**
 * Install a mock interface for windows messaging
 * @param {{
 *  messagingContext: import('../index.js').MessagingContext,
 *  responses: Record<string, any>,
 *  messageCallback: 'messageCallback',
 * }} params
 */
export function mockWindowsMessaging(params) {
    if (!window.__playwright_01) {
        window.__playwright_01 = {
            mockResponses: params.responses,
            subscriptionEvents: [],
            mocks: {
                outgoing: [],
            },
        };
    }
    const listeners = [];
    // @ts-expect-error mocking is intentional
    window.chrome = {};
    // @ts-expect-error mocking is intentional
    window.chrome.webview = {
        /**
         * @param {AnyWindowsMessage} input
         */
        postMessage(input) {
            // subscription events come through here also
            if ('subscriptionName' in input) {
                setTimeout(() => {
                    for (const listener of listeners) {
                        listener({ origin: window.origin, data: input });
                    }
                }, 0);
                return;
            }
            /** @type {NotificationMessage | RequestMessage} */
            let msg = {
                context: input.Feature,
                featureName: input.SubFeatureName,
                params: input.Data,
                method: input.Name,
                id: undefined,
            };

            // add the Id if it was a RequestMessage
            if ('Id' in input) {
                msg = {
                    ...msg,
                    id: input.Id,
                };
            }

            // record the call
            window.__playwright_01.mocks.outgoing.push(
                JSON.parse(
                    JSON.stringify({
                        payload: msg,
                    }),
                ),
            );

            // if there's no 'id' field, we don't need to respond
            if (!('id' in msg)) return;

            // If we get here, it needed a response **and** we have a value for it
            setTimeout(() => {
                // if the mocked response is absent, bail with an error
                if (!(msg.method in window.__playwright_01.mockResponses)) {
                    throw new Error('response not found for ' + msg.method);
                }

                // now access the response
                const response = window.__playwright_01.mockResponses[msg.method];

                for (const listener of listeners) {
                    listener({
                        origin: window.origin,
                        /** @type {Omit<MessageResponse, 'error'>} */
                        data: {
                            result: response,
                            context: msg.context,
                            featureName: msg.featureName,
                            id: msg.id,
                        },
                    });
                }
            }, 0);
        },
        removeEventListener(_name, _listener) {
            const index = listeners.indexOf(_listener);
            if (index > -1) {
                listeners.splice(index, 1);
            }
        },
        addEventListener(_name, listener) {
            listeners.push(listener);
        },
    };
}

/**
 * Install a mock interface for windows messaging
 * @param {{
 *  messagingContext: import('../index.js').MessagingContext,
 *  responses: Record<string, any>
 *  messageCallback: string,
 * }} params
 */
export function mockWindowsInteropMessaging(params) {
    if (!window.__playwright_01) {
        window.__playwright_01 = {
            mockResponses: params.responses,
            subscriptionEvents: [],
            mocks: {
                outgoing: [],
            },
        };
    }
    const listeners = [];
    /**
     * @param {AnyWindowsMessage} input
     */
    window.windowsInteropPostMessage = (input) => {
        // subscription events come through here also
        if ('subscriptionName' in input) {
            setTimeout(() => {
                for (const listener of listeners) {
                    listener({ origin: window.origin, data: input });
                }
            }, 0);
            return;
        }
        /** @type {NotificationMessage | RequestMessage} */
        let msg = {
            context: input.Feature,
            featureName: input.SubFeatureName,
            params: input.Data,
            method: input.Name,
            id: undefined,
        };

        // add the Id if it was a RequestMessage
        if ('Id' in input) {
            msg = {
                ...msg,
                id: input.Id,
            };
        }

        // record the call
        window.__playwright_01.mocks.outgoing.push(
            JSON.parse(
                JSON.stringify({
                    payload: msg,
                }),
            ),
        );

        // if there's no 'id' field, we don't need to respond
        if (!('id' in msg)) return;

        // If we get here, it needed a response **and** we have a value for it
        setTimeout(() => {
            // if the mocked response is absent, bail with an error
            if (!(msg.method in window.__playwright_01.mockResponses)) {
                throw new Error('response not found for ' + msg.method);
            }

            // now access the response
            const response = window.__playwright_01.mockResponses[msg.method];

            for (const listener of listeners) {
                listener({
                    origin: window.origin,
                    /** @type {Omit<MessageResponse, 'error'>} */
                    data: {
                        result: response,
                        context: msg.context,
                        featureName: msg.featureName,
                        id: msg.id,
                    },
                });
            }
        }, 0);
    };
    window.windowsInteropRemoveEventListener = (_name, _listener) => {
        const index = listeners.indexOf(_listener);
        if (index > -1) {
            listeners.splice(index, 1);
        }
    };
    window.windowsInteropAddEventListener = (_name, listener) => {
        listeners.push(listener);
    };
}

/**
 * Install a mock interface for windows messaging
 * @param {{
 *  messagingContext: import('../index.js').MessagingContext,
 *  responses: Record<string, any>,
 *  messageCallback: string,
 * }} params
 */
export function mockWebkitMessaging(params) {
    if (!window.__playwright_01) {
        window.__playwright_01 = {
            mockResponses: params.responses,
            subscriptionEvents: [],
            mocks: {
                outgoing: [],
            },
        };
    }
    window.webkit = {
        messageHandlers: {
            ...window.webkit?.messageHandlers,
            [params.messagingContext.context]: {
                /**
                 * @param {RequestMessage | NotificationMessage} msg
                 */
                async postMessage(msg) {
                    window.__playwright_01.mocks.outgoing.push(
                        JSON.parse(
                            JSON.stringify({
                                payload: msg,
                            }),
                        ),
                    );

                    // force a 'tick' to allow tests to reset mocks before reading responses
                    await new Promise((resolve) => setTimeout(resolve, 0));

                    // if it's a notification, simulate the empty response and don't check for a response
                    if (!('id' in msg)) {
                        return JSON.stringify({});
                    }

                    if (!(msg.method in window.__playwright_01.mockResponses)) {
                        throw new Error('response not found for ' + msg.method);
                    }

                    const response = window.__playwright_01.mockResponses[msg.method];

                    /** @type {Omit<MessageResponse, 'error'>} */
                    const r = {
                        result: response,
                        context: msg.context,
                        featureName: msg.featureName,
                        id: msg.id,
                    };

                    return JSON.stringify(r);
                },
            },
        },
    };
}

/**
 * Install a mock interface for android messaging
 * @param {{
 *  messagingContext: import('../index.js').MessagingContext,
 *  responses: Record<string, any>,
 *  messageCallback: string
 *  javascriptInterface?: string
 * }} params
 */
export function mockAndroidMessaging(params) {
    window.__playwright_01 = {
        mockResponses: params.responses,
        subscriptionEvents: [],
        mocks: {
            outgoing: [],
        },
    };
    if (!params.javascriptInterface) throw new Error('`javascriptInterface` is required for Android mocking');
    window[params.javascriptInterface] = {
        /**
         * @param {string} jsonString
         * @param {string} secret
         * @return {Promise<void>}
         */
        // eslint-disable-next-line require-await
        process: async (jsonString, secret) => {
            /** @type {RequestMessage | NotificationMessage} */
            const msg = JSON.parse(jsonString);

            window.__playwright_01.mocks.outgoing.push(
                JSON.parse(
                    JSON.stringify({
                        payload: msg,
                    }),
                ),
            );

            // if it's a notification, simulate the empty response and don't check for a response
            if (!('id' in msg)) {
                return;
            }

            if (!(msg.method in window.__playwright_01.mockResponses)) {
                throw new Error('response not found for ' + msg.method);
            }

            const response = window.__playwright_01.mockResponses[msg.method];

            /** @type {Omit<MessageResponse, 'error'>} */
            const r = {
                result: response,
                context: msg.context,
                featureName: msg.featureName,
                id: msg.id,
            };

            globalThis[params.messageCallback]?.(secret, r);
        },
    };
}

/**
 * @param {object} params
 * @param {Record<string, any>} params.responses
 */
export function mockResponses(params) {
    window.__playwright_01.mockResponses = {
        ...window.__playwright_01.mockResponses,
        ...params.responses,
    };
}

/**
 * @param {object} params
 * @param {string} params.method
 * @param {number} params.count
 */
export function waitForCallCount(params) {
    const outgoing = window.__playwright_01.mocks.outgoing;
    const filtered = outgoing.filter(({ payload }) => {
        if ('method' in payload) {
            return params.method === payload.method;
        }
        return false;
    });
    return filtered.length >= params.count;
}

/**
 * Just access to readOutgoingMessages
 * @return {any}
 */
export function readOutgoingMessages() {
    return window.__playwright_01.mocks.outgoing;
}

/**
 * simulate what happens in Windows environment where globals get erased
 * @param {string} js
 * @param {Record<string, any>} replacements
 */
export function wrapWindowsScripts(js, replacements) {
    for (const [find, replace] of Object.entries(replacements)) {
        js = js.replace(find, JSON.stringify(replace));
    }
    return `
        (() => {
            try {
                window.windowsInteropPostMessage = window.chrome.webview.postMessage;
                window.windowsInteropAddEventListener = window.chrome.webview.addEventListener;
                window.windowsInteropRemoveEventListener = window.chrome.webview.removeEventListener;
                delete window.chrome.webview.postMessage;
                delete window.chrome.webview.addEventListener;
                delete window.chrome.webview.removeEventListener;
                ${js}
            } catch (e) {
                console.error(e)
            }
        })();
    `;
}

/**
 * simulate what happens in Windows environment where globals get erased
 * @param {string} js
 * @param {Record<string, any>} replacements
 */
export function wrapWebkitScripts(js, replacements) {
    for (const [find, replace] of Object.entries(replacements)) {
        js = js.replace(find, JSON.stringify(replace));
    }
    return js;
}

/**
 * @param {object} params
 * @param {import('../index.js').MessagingContext} params.messagingContext
 * @param {string} params.name
 * @param {Record<string, any>} params.payload
 * @param {NonNullable<ImportMeta['injectName']>} params.injectName
 * @param {string} [params.messageCallback] - optional name of a global method where messages can be delivered (android)
 * @param {string} [params.messageSecret] - optional message secret for platforms that require it (android)
 */
export function simulateSubscriptionMessage(params) {
    const subscriptionEvent = {
        context: params.messagingContext.context,
        featureName: params.messagingContext.featureName,
        subscriptionName: params.name,
        params: params.payload,
    };
    switch (params.injectName) {
        case 'windows': {
            // @ts-expect-error DDG custom global
            const fn = window.chrome?.webview?.postMessage || window.windowsInteropPostMessage;
            fn(subscriptionEvent);
            break;
        }
        case 'android': {
            if (!params.messageCallback || !params.messageSecret)
                throw new Error('`messageCallback` + `messageSecret` needed to simulate subscription event on Android');

            window[params.messageCallback]?.(params.messageSecret, subscriptionEvent);
            break;
        }
        case 'apple':
        case 'apple-isolated': {
            if (!(params.name in window)) throw new Error('subscription fn not found for: ' + params.injectName);
            window[params.name](subscriptionEvent);
            break;
        }
        case 'integration': {
            if (!('publishSubscriptionEvent' in window.__playwright_01))
                throw new Error(
                    `subscription event '${subscriptionEvent.subscriptionName}' was not published because 'window.__playwright_01.publishSubscriptionEvent' was missing`,
                );
            window.__playwright_01.publishSubscriptionEvent?.(subscriptionEvent);
            break;
        }
        default:
            throw new Error('platform not supported yet: ' + params.injectName);
    }
}
