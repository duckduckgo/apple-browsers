import { TestTransportConfig } from '@duckduckgo/messaging';
import { values } from './values.js';

/**
 * @typedef {import('../../types/new-tab.ts').NewTabMessages['subscriptions']['subscriptionEvent']} SubscriptionNames
 * @typedef {import('../../types/new-tab.ts').UserColorData} UserColorData
 */

const url = new URL(window.location.href);

export function customizerMockTransport() {
    let channel;
    if (typeof globalThis.BroadcastChannel !== 'undefined') {
        channel = new BroadcastChannel('ntp_customizer');
    }
    /** @type {Map<SubscriptionNames, any>} */
    const subscriptions = new Map();

    /**
     * @param {SubscriptionNames} named
     * @param {any} data
     */
    function broadcastHere(named, data) {
        setTimeout(() => {
            channel?.postMessage({
                subscriptionName: named,
                params: data,
            });
        }, 100);
    }

    channel?.addEventListener('message', (msg) => {
        if (msg.data.subscriptionName) {
            const cb = subscriptions.get(msg.data.subscriptionName);
            if (!cb) return console.warn(`missing subscription for ${msg.data.subscriptionName}`);
            cb(msg.data.params);
        }
    });

    return new TestTransportConfig({
        notify(_msg) {
            /** @type {import('../../types/new-tab.ts').NewTabMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'customizer_setTheme': {
                    broadcastHere('customizer_onThemeUpdate', msg.params);
                    return;
                }
                case 'customizer_setBackground': {
                    broadcastHere('customizer_onBackgroundUpdate', msg.params);

                    if (msg.params.background.kind === 'hex') {
                        const userColorData = { userColor: msg.params.background };
                        /** @type {UserColorData} */
                        broadcastHere('customizer_onColorUpdate', userColorData);
                    }

                    return;
                }
                default: {
                    console.warn('unhandled customizer notification', msg);
                }
            }
        },
        subscribe(_msg, cb) {
            /** @type {import('../../types/new-tab.ts').NewTabMessages['subscriptions']['subscriptionEvent']} */
            const sub = /** @type {any} */ (_msg.subscriptionName);
            switch (sub) {
                case 'customizer_onColorUpdate':
                case 'customizer_onThemeUpdate':
                case 'customizer_onBackgroundUpdate':
                case 'customizer_onImagesUpdate': {
                    subscriptions.set(sub, cb);
                    console.log('did add sub', sub);
                    return () => {
                        console.log('-- did remove sub', sub);
                        return subscriptions.delete(sub);
                    };
                }
            }
            return () => {};
        },
        // eslint-ignore-next-line require-await
        request(_msg) {
            /** @type {import('../../types/new-tab.ts').NewTabMessages['requests']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                default: {
                    return Promise.reject(new Error('unhandled request' + msg));
                }
            }
        },
    });
}

/**
 * @returns {import("../../types/new-tab.js").DefaultStyles | null}
 */
function getDefaultStyles() {
    if (url.searchParams.get('defaultStyles') === 'visual-refresh') {
        // https://app.asana.com/0/1201141132935289/1209349703167198/f
        return {
            lightBackgroundColor: '#E9EBEC',
            darkBackgroundColor: '#27282A',
        };
    }
    return null;
}

/** @type {()=>import('../../types/new-tab').CustomizerData} */
export function customizerData() {
    /** @type {import('../../types/new-tab').CustomizerData} */
    const customizer = {
        userImages: [],
        userColor: null,
        theme: 'system',
        background: { kind: 'default' },
        defaultStyles: getDefaultStyles(),
    };

    if (url.searchParams.has('background')) {
        const value = url.searchParams.get('background');
        if (value && value in values.colors) {
            customizer.background = {
                kind: 'color',
                value: /** @type {import('../../types/new-tab').PredefinedColor} */ (value),
            };
        } else if (value && value in values.gradients) {
            customizer.background = {
                kind: 'gradient',
                value: /** @type {import('../../types/new-tab').PredefinedGradient} */ (value),
            };
        } else if (value && value.startsWith('hex:')) {
            const hex = value.slice(4);
            if (hex.length === 6 || hex.length === 8) {
                customizer.background = {
                    kind: 'hex',
                    value: `#${hex.slice(0, 6)}`,
                };
            } else {
                console.warn('invalid hex values');
            }
        } else if (value && value.startsWith('userImage:')) {
            const image = value.slice(10);
            if (image in values.userImages) {
                customizer.background = {
                    kind: 'userImage',
                    value: values.userImages[image],
                };
            } else {
                console.warn('unknown user image');
            }
        } else if (value && value === 'default') {
            customizer.background = { kind: 'default' };
        }
    }

    if (url.searchParams.has('userImages')) {
        customizer.userImages = [values.userImages['01'], values.userImages['02'], values.userImages['03']];
        if (url.searchParams.get('willThrowPageException') === 'userImages') {
            customizer.userImages[0] = {
                ...customizer.userImages[0],
                id: '__will_throw__',
            };
        }
    }
    if (url.searchParams.has('userColor')) {
        const hex = `#` + url.searchParams.get('userColor');
        customizer.userColor = { kind: 'hex', value: hex };
    }
    if (url.searchParams.has('theme')) {
        const value = url.searchParams.get('theme');
        if (value === 'light' || value === 'dark' || value === 'system') {
            customizer.theme = value;
        }
    }

    return customizer;
}
