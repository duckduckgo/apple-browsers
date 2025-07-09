/**
 * @typedef {import("../../types/new-tab.js").PrivacyStatsData} PrivacyStatsData
 */
import { Service } from '../service.js';

export class PrivacyStatsService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        /** @type {Service<PrivacyStatsData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('stats_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('stats_onDataUpdate', cb),
        });
    }

    name() {
        return 'PrivacyStatsService';
    }

    /**
     * @returns {Promise<PrivacyStatsData>}
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
    }

    /**
     * @param {(evt: {data: PrivacyStatsData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }
}
