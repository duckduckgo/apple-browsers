import { TestTransportConfig } from '@duckduckgo/messaging';

/**
 * @typedef {import('../../release-notes/types/release-notes.ts').UpdateMessage} UpdateMessage
 */

const url = new URL(window.location.href);

export function mockTransport() {
    return new TestTransportConfig({
        notify(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                default: {
                    console.warn('unhandled notification', msg);
                }
            }
        },
        request(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'init': {
                    const stepDefinitions = {};

                    const adBlocking = url.searchParams.get('adBlocking');
                    if (adBlocking === 'placebo' || adBlocking === 'aggressive' || adBlocking === 'youtube') {
                        stepDefinitions.systemSettings = {
                            id: 'systemSettings',
                            kind: 'settings',
                            rows: ['dock', 'import', `${adBlocking}-ad-blocking`],
                        };
                    }

                    return Promise.resolve({
                        stepDefinitions,
                        exclude: [],
                        order: 'v3',
                        locale: 'en',
                        env: 'development',
                    });
                }
                case 'requestImport':
                case 'requestSetAsDefault':
                case 'requestDockOptIn': {
                    return Promise.resolve({
                        enabled: true,
                    });
                }
                default:
                    return Promise.resolve(null);
            }
        },
        subscribe(_msg, callback) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: structuredClone(_msg) });

            callback(null);

            return () => {
                // any cleanup
            };
        },
    });
}
