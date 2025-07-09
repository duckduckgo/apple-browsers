import { TestTransportConfig } from '@duckduckgo/messaging';
import { activityMocks } from './activity.mocks.js';

const url = typeof window !== 'undefined' ? new URL(window.location.href) : new URL('https://example.com');

/**
 * @typedef {import('../../../types/new-tab.js').ActivityOnDataPatchSubscription['params']} PatchParams
 */

/**
 * @template T
 * @param {T} value
 * @return {T}
 */
function clone(value) {
    return window.structuredClone?.(value) ?? JSON.parse(JSON.stringify(value));
}

export function activityMockTransport() {
    /** @type {import('../../../types/new-tab.ts').ActivityData} */
    let dataset = clone(activityMocks.few);

    if (url.searchParams.has('activity')) {
        const key = url.searchParams.get('activity');
        if (key && key in activityMocks) {
            dataset = clone(activityMocks[key]);
        } else if (key?.match(/^\d+$/)) {
            dataset = getJsonSync(parseInt(key));
        }
    }

    const subs = new Map();

    return new TestTransportConfig({
        notify(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['notifications']} */
            const msg = /** @type {any} */ (_msg);
            switch (msg.method) {
                case 'activity_removeItem': {
                    // grab the tracker count of the current dataset before we alter it
                    const oldCount = dataset.activity.reduce((acc, item) => acc + item.trackingStatus.totalCount, 0);

                    // now filter the items
                    dataset.activity = dataset.activity.filter((x) => x.url !== msg.params.url);

                    // create the patch dataset, and use the original tracker count
                    const patchParams = toPatch(dataset.activity);
                    patchParams.totalTrackersBlocked = oldCount;

                    // simulate the native side pushing the fresh data back into the page.
                    setTimeout(() => {
                        const cb = subs.get('activity_onDataPatch');
                        cb(patchParams);
                    }, 0);
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
            if (sub === 'activity_onBurnComplete') {
                subs.set('activity_onBurnComplete', cb);
                return () => {
                    subs.delete('activity_onBurnComplete');
                };
            }
            if (sub === 'activity_onDataUpdate') {
                subs.set('activity_onDataUpdate', cb);
            }
            if (sub === 'activity_onDataPatch') {
                subs.set('activity_onDataPatch', cb);
            }
            if (sub === 'activity_onDataUpdate' && url.searchParams.has('flood')) {
                let count = 0;
                const int = setInterval(() => {
                    if (count === 10) return clearInterval(int);
                    dataset.activity.push({
                        url: `https://${count}.example.com`,
                        etldPlusOne: 'example.com',
                        favicon: null,
                        history: [],
                        favorite: false,
                        trackersFound: false,
                        trackingStatus: { trackerCompanies: [], totalCount: 0 },
                        title: 'example.com',
                    });
                    count += 1;
                    console.log('sent', dataset);
                    cb(dataset);
                }, 1000);
                return () => {};
            }
            if (sub === 'activity_onDataUpdate' && url.searchParams.has('nested')) {
                let count = 0;
                const int = setInterval(() => {
                    if (count === 10) return clearInterval(int);
                    dataset.activity[1].history.push({
                        url: `https://${count}.example.com`,
                        title: 'example.com',
                        relativeTime: 'just now',
                    });
                    // next.activity[0].trackingStatus.trackerCompanies.push({
                    //     displayName: `${count}.example.com`,
                    // });
                    // next.activity[0].trackingStatus.trackerCompanies.push({
                    //     displayName: `${count}.example.com`,
                    // });
                    // next.activity[0].trackingStatus.totalCount += 1;
                    count += 1;
                    cb(dataset);
                }, 500);
                return () => {};
            }

            if (sub === 'activity_onDataPatch') {
                /** @type {any} */ (window).af = {
                    gen(count) {
                        return generateSampleData(count);
                    },
                    patchAddBack(count) {
                        const len = dataset.activity.length;
                        const all = generateSampleData(200);
                        const newItems = all.slice(len, len + count);
                        dataset.activity.push(...newItems);
                        const patch = toPatch(dataset.activity);
                        cb(patch);
                    },
                    patchAddFront(count) {
                        const len = dataset.activity.length;
                        const all = generateSampleData(200);
                        const newItems = all.slice(len, len + count);
                        dataset.activity = [...newItems, ...dataset.activity];
                        const patch = toPatch(dataset.activity);
                        cb(patch);
                    },
                    patchRemove(nth) {
                        dataset.activity.splice(nth, 1);
                        const patch = toPatch(dataset.activity);
                        cb(patch);
                    },
                    patchRemoveCount(count) {
                        dataset.activity.splice(dataset.activity.length - count, count);
                        const patch = toPatch(dataset.activity);
                        cb(patch);
                    },
                    addHistoryEntry(nth) {
                        const item = dataset.activity[nth];
                        item.history.push({
                            title: 'pushed history entry',
                            url: item.url + '/h1',
                            relativeTime: 'Just now',
                        });
                        // dataset.activity.splice(dataset.activity.length - count, count);
                        const patch = toPatchItem(dataset.activity, nth);
                        cb(patch);
                    },
                    addTrackingCompany(nth) {
                        const item = dataset.activity[nth];
                        item.trackingStatus.trackerCompanies.push({
                            displayName: 'Bytedance',
                        });
                        // dataset.activity.splice(dataset.activity.length - count, count);
                        const patch = toPatchItem(dataset.activity, nth);
                        cb(patch);
                    },
                    increaseTrackerCount(nth) {
                        const item = dataset.activity[nth];
                        item.trackingStatus.totalCount += 1;
                        // dataset.activity.splice(dataset.activity.length - count, count);
                        const patch = toPatchItem(dataset.activity, nth);
                        cb(patch);
                    },
                };
                return () => {};
            }

            console.warn('unhandled sub', sub);
            return () => {};
        },
        // eslint-ignore-next-line require-await
        request(_msg) {
            /** @type {import('../../../types/new-tab.ts').NewTabMessages['requests']} */
            const msg = /** @type {any} */ (_msg);
            console.log(msg);
            switch (msg.method) {
                case 'activity_confirmBurn': {
                    const url = msg.params.url;
                    /** @type {import('../../../types/new-tab.ts').ConfirmBurnResponse} */
                    let response = { action: 'burn' };

                    /**
                     * When not in automated tests, use a confirmation window to mimic the native modal
                     */
                    if (!window.__playwright_01) {
                        const fireproof = url.startsWith('https://fireproof.');
                        if (fireproof) {
                            if (!confirm('are you sure?')) {
                                response = { action: 'none' };
                            }
                        }
                    }

                    if (response.action === 'burn' && !window.__playwright_01) {
                        setTimeout(() => {
                            const cb = subs.get('activity_onDataUpdate');
                            console.log('will send updated data after 500ms', url);
                            const next = activityMocks.few.activity.filter((x) => x.url !== url);
                            cb?.({ activity: next });
                        }, 500);
                        setTimeout(() => {
                            const cb = subs.get('activity_onBurnComplete');
                            console.log('will send updated data after 600ms', url);
                            cb?.();
                        }, 600);
                    }

                    return Promise.resolve(response);
                }
                case 'activity_getUrls': {
                    /** @type {import('../../../types/new-tab.ts').ActivityGetUrlsRequest['result']} */
                    const next = toPatch(dataset.activity);
                    return Promise.resolve(next);
                }
                case 'activity_getDataForUrls': {
                    /** @type {import('../../../types/new-tab.ts').ActivityGetDataForUrlsRequest['result']} */
                    const next = {
                        activity: dataset.activity.filter((x) => msg.params.urls.includes(x.url)),
                    };
                    return Promise.resolve(next);
                }
                case 'activity_getData':
                    return Promise.resolve(dataset);
                default: {
                    return Promise.reject(new Error('unhandled request' + msg));
                }
            }
        },
    });
}

/**
 * @returns {import('../../../types/new-tab.ts').ActivityData}
 */
function getJsonSync(count = 200) {
    return { activity: generateSampleData(count) };
}

/**
 * @param {import('../../../types/new-tab.ts').DomainActivity[]} entries
 * @return {PatchParams}
 */
function toPatch(entries) {
    return {
        urls: entries.map((x) => x.url),
        totalTrackersBlocked: entries.reduce((acc, item) => acc + item.trackingStatus.totalCount, 0),
    };
}
/**
 * @param {import('../../../types/new-tab.ts').DomainActivity[]} entries
 * @param {number} nth
 * @return {PatchParams}
 */
function toPatchItem(entries, nth) {
    return {
        urls: entries.map((x) => x.url),
        totalTrackersBlocked: entries.reduce((acc, item) => acc + item.trackingStatus.totalCount, 0),
        patch: entries[nth],
    };
}

/**
 * @param {number} count
 * @returns {import('../../../types/new-tab.ts').DomainActivity[]}
 */
export function generateSampleData(count) {
    // Deterministic string generator based on an index
    const generateString = (index, length = 10) => {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'; // Define a string of all possible characters (alphanumeric)
        let result = ''; // Initialize an empty string to store the result
        const seed = index; // Use index as a seed for pseudo-randomness
        for (let i = 0; i < length; i++) {
            // Loop for the specified length of the string
            result += chars.charAt((seed + i * 17) % chars.length); // Add a character at a calculated position within the chars string
        }
        return result; // Return the generated string
    };

    const generateHistoryItem = (parentIndex, historyIndex) => ({
        title: `(h) ${parentIndex}.${historyIndex} - ${generateString(historyIndex, 12)}`,
        url: `https://${parentIndex}.${generateString(parentIndex)}.com/a`,
        relativeTime: historyIndex === 0 ? '5 minutes ago' : '3 weeks ago',
    });

    const generateTrackerCompanies = (index) => {
        // Using 20 common companies identified as trackers
        const companies = [
            { displayName: 'Google' },
            { displayName: 'Facebook' },
            { displayName: 'Amazon' },
            { displayName: 'Microsoft' },
            { displayName: 'Apple' },
            { displayName: 'Twitter' },
            { displayName: 'Adobe' },
            { displayName: 'Oracle' },
            { displayName: 'TikTok' },
            { displayName: 'LinkedIn' },
            { displayName: 'Spotify' },
            { displayName: 'Snapchat' },
            { displayName: 'Yahoo' },
            { displayName: 'Cloudflare' },
            { displayName: 'Dropbox' },
            { displayName: 'Reddit' },
            { displayName: 'Pinterest' },
            { displayName: 'Salesforce' },
            { displayName: 'IBM' },
            { displayName: 'Tencent' },
        ];
        const itemCount = index % 6; // Wrap from 0 to 5
        return companies.slice(0, itemCount);
    };

    const data = [];
    for (let i = 0; i < count; i++) {
        const generatedString = generateString(i);
        const trackerCompanies = generateTrackerCompanies(i);
        data.push({
            title: `${i} ${generatedString}`,
            url: `https://${i}.${generatedString}.com`,
            etldPlusOne: `${generatedString}.com`,
            trackersFound: true,
            history: [generateHistoryItem(i, 0), generateHistoryItem(i, 1)],
            favorite: false,
            favicon: null,
            trackingStatus: {
                trackerCompanies,
                totalCount: trackerCompanies.length === 0 ? 0 : Math.round(trackerCompanies.length * 1.5),
            },
        });
    }
    return data;
}

// console.log(JSON.stringify(generateSampleData(10), null, 2));
