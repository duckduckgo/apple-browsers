/**
 * @typedef {import("../../types/new-tab.js").ProtectionsData} ProtectionsData
 * @typedef {import("../../types/new-tab.js").ProtectionsConfig} ProtectionsConfig
 */
import { Service } from '../service.js';

export class ProtectionsService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        /** @type {Service<ProtectionsData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('protections_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('protections_onDataUpdate', cb),
        });

        /** @type {Service<ProtectionsConfig>} */
        this.configService = new Service({
            initial: () => ntp.messaging.request('protections_getConfig'),
            subscribe: (cb) => ntp.messaging.subscribe('protections_onConfigUpdate', cb),
            persist: (data) => ntp.messaging.notify('protections_setConfig', data),
        });
    }

    name() {
        return 'ProtectionsService';
    }

    /**
     * @returns {Promise<{data: ProtectionsData; config: ProtectionsConfig}>}
     * @internal
     */
    async getInitial() {
        const p1 = this.configService.fetchInitial();
        const p2 = this.dataService.fetchInitial();
        const [config, data] = await Promise.all([p1, p2]);
        return { config, data };
    }

    /**
     * @internal
     */
    destroy() {
        this.configService.destroy();
        this.dataService.destroy();
    }

    /**
     * @param {(evt: {data: ProtectionsData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }

    /**
     * @param {(evt: {data: ProtectionsConfig, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onConfig(cb) {
        return this.configService.onData(cb);
    }

    /**
     * Update the in-memory data immediate and persist.
     * Any state changes will be broadcast to consumers synchronously
     * @internal
     */
    toggleExpansion() {
        this.configService.update((old) => {
            if (old.expansion === 'expanded') {
                return { ...old, expansion: /** @type {const} */ ('collapsed') };
            } else {
                return { ...old, expansion: /** @type {const} */ ('expanded') };
            }
        });
    }

    /**
     * @param {ProtectionsConfig['feed']} feed
     */
    setFeed(feed) {
        this.configService.update((old) => {
            return {
                ...old,
                feed,
            };
        });
    }
}
