/**
 * @typedef {import("../../types/new-tab.js").ActivityData} ActivityData
 * @typedef {import("../../types/new-tab.js").UrlInfo} UrlInfo
 * @typedef {import("../../types/new-tab.js").PatchData} PatchData
 * @typedef {import('../../types/new-tab.js').DomainActivity} DomainActivity
 * @typedef {import('../service.js').InvocationSource} InvocationSource
 */
import { Service } from '../service.js';

/**
 * @typedef {{ activity: DomainActivity[], urls: string[], totalTrackers: number }} Incoming
 */

export class BatchedActivityService {
    INITIAL = 5;
    CHUNK_SIZE = 10;
    isFetchingNext = false;
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @param {boolean} batched
     * @internal
     */
    constructor(ntp, batched = false) {
        this.ntp = ntp;
        this.batched = batched;

        /** @type {Service<Incoming>} */
        this.dataService = new Service({
            initial: async (params) => {
                if (this.batched) {
                    if (params && Array.isArray(params.urls) && this.dataService.data?.urls) {
                        const data = await this.ntp.messaging.request('activity_getDataForUrls', {
                            urls: params.urls,
                        });
                        return {
                            activity: data.activity,
                            totalTrackers: this.dataService.data.totalTrackers,
                            urls: this.dataService.data.urls,
                        };
                    } else {
                        const urlsResponse = await this.ntp.messaging.request('activity_getUrls');
                        const data = await this.ntp.messaging.request('activity_getDataForUrls', {
                            urls: urlsResponse.urls.slice(0, this.INITIAL),
                        });
                        return { activity: data.activity, urls: urlsResponse.urls, totalTrackers: urlsResponse.totalTrackersBlocked };
                    }
                } else {
                    const data = await this.ntp.messaging.request('activity_getData');
                    return {
                        activity: data.activity,
                        urls: data.activity.map((x) => x.url),
                        totalTrackers: data.activity.reduce((acc, item) => acc + item.trackingStatus.totalCount, 0),
                    };
                }
            },
            subscribe: (cb) => {
                const sub1 = ntp.messaging.subscribe('activity_onDataUpdate', (params) => {
                    cb({
                        activity: params.activity,
                        urls: params.activity.map((x) => x.url),
                        totalTrackers: params.activity.reduce((acc, item) => acc + item.trackingStatus.totalCount, 0),
                    });
                });
                const sub2 = ntp.messaging.subscribe('activity_onDataPatch', (params) => {
                    const totalTrackers = params.totalTrackersBlocked;
                    if ('patch' in params && params.patch !== null) {
                        cb({ activity: [/** @type {DomainActivity} */ (params.patch)], urls: params.urls, totalTrackers });
                    } else {
                        cb({ activity: [], urls: params.urls, totalTrackers });
                    }
                });
                return () => {
                    sub1();
                    sub2();
                };
            },
        }).withUpdater((old, next, source) => {
            if (source === 'manual') {
                return next;
            }
            if (this.batched) {
                return {
                    activity: old.activity.concat(next.activity),
                    urls: next.urls,
                    totalTrackers: next.totalTrackers,
                };
            }
            return next;
        });

        /** @type {EventTarget|null} */
        this.burns = new EventTarget();
        this.burnUnsub = this.ntp.messaging.subscribe('activity_onBurnComplete', () => {
            this.burns?.dispatchEvent(new CustomEvent('activity_onBurnComplete'));
        });
    }

    name() {
        return 'BatchedActivity';
    }

    /**
     * @returns {Promise<ActivityData>}
     * @internal
     */
    async getInitial() {
        return await this.dataService.fetchInitial();
    }

    /**
     * @internal
     */
    destroy() {
        this.dataService.destroy();
        this.burnUnsub();
        this.burns = null;
    }

    /**
     * @param {string[]} urls
     */
    next(urls) {
        if (urls.length === 0) return;
        this.isFetchingNext = true;
        this.dataService.triggerFetch({ urls });
    }

    /**
     * @param {(evt: {data: Incoming, source: InvocationSource}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData((data) => {
            this.isFetchingNext = false;
            cb(data);
        });
    }

    /**
     * @param {string[]} [urls] - optional subset to refresh
     */
    triggerDataFetch(urls) {
        if (urls) {
            this.dataService.triggerFetch({ urls });
        } else {
            this.dataService.triggerFetch();
        }
    }
    /**
     * @param {string} url
     */
    addFavorite(url) {
        this.dataService.update((old) => {
            return {
                ...old,
                activity: old.activity.map((item) => {
                    if (item.url === url) return { ...item, favorite: true };
                    return item;
                }),
            };
        });
        this.ntp.messaging.notify('activity_addFavorite', { url });
    }
    /**
     * @param {string} url
     */
    removeFavorite(url) {
        this.dataService.update((old) => {
            return {
                ...old,
                activity: old.activity.map((item) => {
                    if (item.url === url) return { ...item, favorite: false };
                    return item;
                }),
            };
        });
        this.ntp.messaging.notify('activity_removeFavorite', { url });
    }
    /**
     * @param {string} url
     * @return {Promise<import('../../types/new-tab.js').ConfirmBurnResponse>}
     */
    confirmBurn(url) {
        return this.ntp.messaging.request('activity_confirmBurn', { url });
    }
    /**
     * @param {string} url
     */
    remove(url) {
        this.dataService.update((old) => {
            return {
                ...old,
                activity: old.activity.filter((item) => {
                    return item.url !== url;
                }),
                urls: old.urls.filter((x) => x !== url),
            };
        });
        this.ntp.messaging.notify('activity_removeItem', { url });
    }
    /**
     * @param {string} url
     * @param {import('../../types/new-tab.js').OpenTarget} target
     */
    openUrl(url, target) {
        this.ntp.messaging.notify('activity_open', { url, target });
    }

    onBurnComplete(cb) {
        if (!this.burns) throw new Error('unreachable');
        this.burns.addEventListener('activity_onBurnComplete', cb);
        return () => {
            if (!this.burns) throw new Error('unreachable');
            this.burns.removeEventListener('activity_onBurnComplete', cb);
        };
    }

    enableBroadcast() {
        this.dataService.enableBroadcast();
        this.dataService.flush();
    }
    disableBroadcast() {
        this.dataService.disableBroadcast();
    }
}
