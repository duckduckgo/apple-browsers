/**
 * @typedef {import("../../types/new-tab.js").FreemiumPIRBannerData} FreemiumPIRBannerData
 */
import { Service } from '../service.js';

export class FreemiumPIRBannerService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        this.ntp = ntp;
        /** @type {Service<FreemiumPIRBannerData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('freemiumPIRBanner_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('freemiumPIRBanner_onDataUpdate', cb),
        });
    }

    name() {
        return 'FreemiumPIRBannerService';
    }

    /**
     * @returns {Promise<FreemiumPIRBannerData>}
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
     * @param {(evt: {data: FreemiumPIRBannerData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }

    /**
     * @param {string} id
     * @internal
     */
    dismiss(id) {
        return this.ntp.messaging.notify('freemiumPIRBanner_dismiss', { id });
    }

    /**
     * @param {string} id
     */
    action(id) {
        this.ntp.messaging.notify('freemiumPIRBanner_action', { id });
    }
}
