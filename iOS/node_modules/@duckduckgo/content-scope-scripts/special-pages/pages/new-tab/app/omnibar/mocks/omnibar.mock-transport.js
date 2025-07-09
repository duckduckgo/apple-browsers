import { TestTransportConfig } from '@duckduckgo/messaging';
import { getMockSuggestions } from './omnibar.mocks.js';

const url = typeof window !== 'undefined' ? new URL(window.location.href) : new URL('https://example.com');

export function omnibarMockTransport() {
    /** @type {import('../../../types/new-tab.ts').OmnibarConfig} */
    const config = {
        mode: 'search',
    };

    /** @type {Map<string, (d: any) => void>} */
    const subs = new Map();

    return new TestTransportConfig({
        notify(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'omnibar_setConfig': {
                    Object.assign(config, msg.params);
                    subs.get('omnibar_onConfigUpdate')?.(config);
                    break;
                }
                default: {
                    console.warn('unhandled notification', msg);
                }
            }
        },
        subscribe(_msg, cb) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['subscriptions']['subscriptionEvent']} */
            const sub = /** @type {any} */ (_msg.subscriptionName);
            if (sub === 'omnibar_onConfigUpdate') {
                subs.set(sub, cb);
                return () => {};
            }
            console.warn('unhandled sub', sub);
            return () => {};
        },
        async request(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['requests']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'omnibar_getConfig': {
                    const modeOverride = url.searchParams.get('omnibar.mode');
                    if (modeOverride === 'search' || modeOverride === 'ai') {
                        config.mode = modeOverride;
                    }
                    const enableAiOverride = url.searchParams.get('omnibar.enableAi');
                    if (enableAiOverride === 'true' || enableAiOverride === 'false') {
                        config.enableAi = enableAiOverride === 'true';
                    }
                    return config;
                }
                case 'omnibar_getSuggestions': {
                    await new Promise((resolve) => setTimeout(resolve, 100)); // Simulate network delay
                    return getMockSuggestions(msg.params.term);
                }
                default: {
                    throw new Error('unhandled request' + msg);
                }
            }
        },
    });
}
