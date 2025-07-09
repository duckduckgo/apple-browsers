import {
    mockAndroidMessaging,
    mockWebkitMessaging,
    mockWindowsInteropMessaging,
    mockWindowsMessaging,
    readOutgoingMessages,
    simulateSubscriptionMessage,
    waitForCallCount,
} from '@duckduckgo/messaging/lib/test-utils.mjs';

export class Mocks {
    /**
     * @type {Record<string, any>}
     * @private
     */
    _defaultResponses = {};

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("injected/integration-test/type-helpers.mjs").Build} build
     * @param {import("injected/integration-test/type-helpers.mjs").PlatformInfo} platform
     * @param {import("@duckduckgo/messaging").MessagingContext} messagingContext
     */
    constructor(page, build, platform, messagingContext) {
        this.page = page;
        this.build = build;
        this.platform = platform;
        this.messagingContext = messagingContext;
    }

    /**
     * @returns {Promise<void|*|string>}
     */
    async install() {
        this.page.on('console', (msg) => {
            console.log('->', msg.type(), msg.text());
        });
        await this.installMessagingMocks();
    }

    async installMessagingMocks() {
        await this.build.switch({
            windows: async () => {
                await this.page.addInitScript(mockWindowsInteropMessaging, {
                    messagingContext: this.messagingContext,
                    responses: this._defaultResponses,
                    messageCallback: 'messageCallback',
                });
            },
            apple: async () => {
                await this.page.addInitScript(mockWebkitMessaging, {
                    messagingContext: this.messagingContext,
                    responses: this._defaultResponses,
                    messageCallback: 'messageCallback',
                });
            },
            android: async () => {
                await this.page.addInitScript(mockAndroidMessaging, {
                    messagingContext: this.messagingContext,
                    responses: this._defaultResponses,
                    messageCallback: 'messageCallback',
                    javascriptInterface: this.messagingContext.context,
                });
            },
            integration: async () => {
                await this.page.addInitScript(mockWindowsMessaging, {
                    messagingContext: this.messagingContext,
                    responses: this._defaultResponses,
                    messageCallback: 'messageCallback',
                });
            },
        });
    }

    /**
     * @param {Record<string, any>} responses
     */
    defaultResponses(responses) {
        this._defaultResponses = responses;
    }

    /**
     * @param {string} name
     * @param {Record<string, any>} payload
     */
    async simulateSubscriptionMessage(name, payload) {
        await this.page.evaluate(simulateSubscriptionMessage, {
            messagingContext: this.messagingContext,
            name,
            payload,
            injectName: this.build.name,
        });
    }

    /**
     * @param {{names: string[]}} [opts]
     * @returns {Promise<any[]>}
     */
    async outgoing(opts = { names: [] }) {
        const result = await this.page.evaluate(readOutgoingMessages);
        if (Array.isArray(opts.names) && opts.names.length > 0) {
            return result.filter(({ payload }) => opts.names.includes(payload.method));
        }
        return result;
    }

    /**
     * @param {object} params
     * @param {string} params.method
     * @param {number} params.count
     * @param {number} [params.timeout]
     * @return {Promise<*>}
     */
    async waitForCallCount(params) {
        await this.page.waitForFunction(waitForCallCount, params, {
            timeout: params.timeout ?? 3000,
            polling: 100,
        });
        return this.outgoing({ names: [params.method] });
    }
}
