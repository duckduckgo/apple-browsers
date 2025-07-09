import { TestTransportConfig } from '@duckduckgo/messaging';
import { protectionsMocks } from './protections.mocks.js';

const url = typeof window !== 'undefined' ? new URL(window.location.href) : new URL('https://example.com');

/**
 * @template T
 * @param {T} value
 * @return {T}
 */
function clone(value) {
    return window.structuredClone?.(value) ?? JSON.parse(JSON.stringify(value));
}

export function protectionsMockTransport() {
    /** @type {import('../../../types/new-tab.ts').ProtectionsData} */
    let dataset = clone(protectionsMocks.few);
    /** @type {import('../../../types/new-tab.ts').ProtectionsConfig} */
    const config = {
        expansion: 'expanded',
        feed: 'privacy-stats',
    };

    if (url.searchParams.has('protections')) {
        const key = url.searchParams.get('protections');
        if (key && key in protectionsMocks) {
            dataset = clone(protectionsMocks[key]);
        } else {
            console.warn('unknown mock dataset for', key);
        }
    }

    /** @type {Map<string, (d: any) => void>} */
    const subs = new Map();

    return new TestTransportConfig({
        notify(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'protections_setConfig': {
                    Object.assign(config, msg.params);
                    subs.get('protections_onConfigUpdate')?.(config);
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
            if (sub === 'protections_onDataUpdate') {
                subs.set(sub, cb);
                if (url.searchParams.get('protections.continuous')) {
                    const int = setInterval(() => {
                        dataset.totalCount += 1;
                        subs.get(sub)?.(dataset);
                    }, 1000);
                    return () => {
                        console.log('did cleanup');
                        clearInterval(int);
                    };
                }
            }
            if (sub === 'protections_onConfigUpdate') {
                subs.set(sub, cb);
                return () => {};
            }
            console.warn('unhandled sub', sub);
            return () => {};
        },
        // eslint-ignore-next-line require-await
        request(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['requests']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'protections_getData':
                    if (url.searchParams.get('stats') === 'none') {
                        dataset.totalCount = 0;
                    }
                    if (url.searchParams.get('activity') === 'empty') {
                        dataset.totalCount = 0;
                    }
                    return Promise.resolve(dataset);
                case 'protections_getConfig': {
                    if (url.searchParams.get('protections.feed') === 'activity') {
                        config.feed = 'activity';
                    }

                    if (url.searchParams.get('protections.burn') === 'false') {
                        config.showBurnAnimation = false;
                    }

                    return Promise.resolve(config);
                }
                default: {
                    return Promise.reject(new Error('unhandled request' + msg));
                }
            }
        },
    });
}
