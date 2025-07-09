import { TestTransportConfig } from '@duckduckgo/messaging';
import { asResponse, generateSampleData, historyMocks } from './history.mocks.js';

const url = new URL(window.location.href);

/**
 * @typedef {import('@duckduckgo/messaging/lib/test-utils.mjs').SubscriptionEvent} SubscriptionEvent
 */

/**
 * @template T
 * @param {T} value
 * @return {T}
 */
function clone(value) {
    return window.structuredClone?.(value) ?? JSON.parse(JSON.stringify(value));
}

export function mockTransport() {
    /** @type {Map<string, (d: any)=>void>} */
    const subscriptions = new Map();
    if ('__playwright_01' in window) {
        window.__playwright_01.publishSubscriptionEvent = (/** @type {SubscriptionEvent} */ evt) => {
            const matchingCallback = subscriptions.get(evt.subscriptionName);
            if (!matchingCallback) return console.error('no matching callback for subscription', evt);
            matchingCallback(evt.params);
        };
    }

    let memory = clone(historyMocks.few).value;
    /** @type {import('../../types/history.ts').GetRangesResponse} */
    const rangeMemory = {
        ranges: [
            { id: 'all', count: 1 },
            { id: 'today', count: 1 },
            { id: 'yesterday', count: 1 },
            { id: 'tuesday', count: 1 },
            { id: 'monday', count: 1 },
            { id: 'sunday', count: 1 },
            { id: 'saturday', count: 1 },
            { id: 'friday', count: 1 },
            { id: 'older', count: 1 },
        ],
    };

    if (url.searchParams.has('history')) {
        const key = url.searchParams.get('history');
        if (key && key in historyMocks) {
            memory = clone(historyMocks[key]).value;
        } else if (key?.match(/^\d+$/)) {
            memory = generateSampleData({ count: parseInt(key), offset: 0 });
        }
    }
    // console.log(memory);
    return new TestTransportConfig({
        notify(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: clone(_msg) });
            /** @type {import('../../types/history.ts').HistoryMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            console.warn('unhandled notification', msg);
        },
        subscribe(_msg, cb) {
            const sub = /** @type {any} */ (_msg.subscriptionName);

            if ('__playwright_01' in window) {
                window.__playwright_01?.mocks?.outgoing?.push?.({ payload: clone(_msg) });
                subscriptions.set(sub, cb);
                return () => {
                    subscriptions.delete(sub);
                };
            }

            console.warn('unhandled subscription', _msg);

            return () => {};
        },
        // eslint-ignore-next-line require-await
        request(_msg) {
            window.__playwright_01?.mocks?.outgoing?.push?.({ payload: clone(_msg) });
            /** @type {import('../../types/history.ts').HistoryMessages['requests']} */
            const msg = /** @type {any} */ (_msg);

            switch (msg.method) {
                case 'query': {
                    return withLatency(queryResponseFrom(memory, msg));
                }
                case 'entries_delete': {
                    // console.log('📤 [entries_delete]: ', JSON.stringify(msg.params));
                    if (msg.params.ids.length > 1) {
                        // prettier-ignore
                        const lines = [
                            `entries_delete: ${JSON.stringify(msg.params)}`,
                            `To simulate deleting these items, press confirm`
                        ].join('\n');
                        if (confirm(lines)) {
                            return Promise.resolve({ action: 'delete' });
                        } else {
                            return Promise.resolve({ action: 'none' });
                        }
                    }
                    return Promise.resolve({ action: 'delete' });
                }
                case 'entries_menu': {
                    // console.log('📤 [entries_menu]: ', JSON.stringify(msg.params));
                    const isSingle = msg.params.ids.length === 1;
                    if (isSingle) {
                        if (url.searchParams.get('action') === 'domain-search') {
                            // prettier-ignore
                            const lines = [
                                `entries_menu: ${JSON.stringify(msg.params.ids)}`,
                                `To simulate pressing 'show more from this url', press confirm`
                            ].join('\n');
                            if (confirm(lines)) {
                                return Promise.resolve({ action: 'domain-search' });
                            } else {
                                return Promise.resolve({ action: 'none' });
                            }
                        }
                    }
                    // prettier-ignore
                    const lines = [
                        `entries_menu: ${JSON.stringify(msg.params)}`,
                        `To simulate deleting these items, press confirm`
                    ].join('\n');
                    if (confirm(lines)) {
                        return Promise.resolve({ action: 'delete' });
                    }
                    return Promise.resolve({ action: 'none' });
                }
                case 'deleteDomain': {
                    // console.log('📤 [deleteDomain]: ', JSON.stringify(msg.params));
                    // prettier-ignore
                    const lines = [
                        `deleteDomain: ${JSON.stringify(msg.params)}`,
                        `To simulate deleting this item, press confirm`
                    ].join('\n',);
                    if (confirm(lines)) {
                        return Promise.resolve({ action: 'delete' });
                    }
                    return Promise.resolve({ action: 'none' });
                }
                case 'deleteTerm': {
                    // console.log('📤 [deleteTerm]: ', JSON.stringify(msg.params));
                    // prettier-ignore
                    const lines = [
                        `deleteTerm: ${JSON.stringify(msg.params)}`,
                        `To simulate deleting this term, press confirm`
                    ].join('\n',);
                    if (confirm(lines)) {
                        return Promise.resolve({ action: 'delete' });
                    }
                    return Promise.resolve({ action: 'none' });
                }
                case 'initialSetup': {
                    /** @type {import('../../types/history.ts').InitialSetupResponse} */
                    const initial = {
                        platform: { name: 'integration' },
                        env: 'development',
                        locale: 'en',
                        customizer: {
                            defaultStyles: getDefaultStyles(),
                        },
                    };

                    return Promise.resolve(initial);
                }

                case 'deleteRange': {
                    // console.log('📤 [deleteRange]: ', JSON.stringify(msg.params));
                    // prettier-ignore
                    const lines = [
                        `deleteRange: ${JSON.stringify(msg.params)}`,
                        `To simulate deleting this item, press confirm`
                    ].join('\n',);
                    if (confirm(lines)) {
                        if (msg.params.range === 'all') memory = [];
                        rangeMemory.ranges = rangeMemory.ranges.filter((x) => {
                            return x.id !== msg.params.range;
                        });
                        console.log(rangeMemory.ranges);
                        return Promise.resolve({ action: 'delete' });
                    }
                    return Promise.resolve({ action: 'none' });
                }
                case 'getRanges': {
                    if (url.searchParams.get('history') === '0') {
                        rangeMemory.ranges = rangeMemory.ranges.map((range) => {
                            return { ...range, count: 0 };
                        });
                    }
                    return Promise.resolve(rangeMemory);
                }
                default: {
                    return Promise.reject(new Error('unhandled request' + msg));
                }
            }
        },
    });
}

/**
 * @returns {import("../../types/history").DefaultStyles | null}
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

async function withLatency(value) {
    let queryLatency = 50;
    const fromParam = url.searchParams.get('query.latency');
    if (fromParam && fromParam.match(/^\d+$/)) {
        queryLatency = parseInt(fromParam, 10);
    }

    await new Promise((resolve) => setTimeout(resolve, queryLatency));

    return value;
}

/**
 * @param {import("../../types/history").HistoryQueryResponse['value']} memory
 * @param {import('../../types/history.ts').QueryRequest} msg
 * @returns {import('../../types/history.ts').HistoryQueryResponse}
 */
function queryResponseFrom(memory, msg) {
    // console.log('📤 [query]: ', JSON.stringify(msg.params));

    if ('term' in msg.params.query) {
        const { term } = msg.params.query;
        if (term !== '') {
            if (term === 'empty' || term.includes('"') || term.includes('<')) {
                const response = asResponse([], msg.params.offset, msg.params.limit);
                response.info.query = { term };
                return response;
            }
            if (term === 'empty') {
                const response = asResponse([], msg.params.offset, msg.params.limit);
                response.info.query = { term };
                return response;
            }
            if (term.trim().match(/^\d+$/)) {
                const int = parseInt(term.trim(), 10);
                /** @type {import("../../types/history").HistoryQueryResponse} */
                const response = asResponse(memory.slice(0, int), msg.params.offset, msg.params.limit);
                response.value = response.value.map((item) => {
                    return {
                        ...item,
                        title: 't:' + term + ' ' + item.title,
                    };
                });
                response.info.query = { term };
                return response;
            }

            /** @type {import("../../types/history").HistoryQueryResponse} */
            const response = asResponse(memory.slice(0, 10), msg.params.offset, msg.params.limit);
            response.info.query = { term };
            return response;
        }
    } else if ('range' in msg.params.query) {
        const response = asResponse(memory.slice(0, 10), msg.params.offset, msg.params.limit);
        const range = msg.params.query.range;
        response.value = response.value.map((item) => {
            return {
                ...item,
                title: 'range:' + range + ' ' + item.title,
            };
        });
        response.info.query = msg.params.query;
        return response;
    } else if ('domain' in msg.params.query) {
        const response = asResponse(memory.slice(0, 10), msg.params.offset, msg.params.limit);
        const domain = msg.params.query.domain;
        response.value = response.value.map((item) => {
            return {
                ...item,
                title: 'domain:' + domain + ' ' + item.title,
            };
        });
        response.info.query = msg.params.query;
        return response;
    }

    /** @type {import("../../types/history").HistoryQueryResponse} */
    return asResponse(memory, msg.params.offset, msg.params.limit);
}
