/**
 * @typedef {import("../../types/new-tab.js").RMFData} RMFData
 */
import { Service } from '../service.js';

export class RMFService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        this.ntp = ntp;
        /** @type {Service<RMFData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('rmf_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('rmf_onDataUpdate', cb),
        });
    }

    name() {
        return 'RMFService';
    }

    /**
     * @returns {Promise<RMFData>}
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
     * @param {(evt: {data: RMFData, source: 'manual' | 'subscription'}) => void} cb
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
        return this.ntp.messaging.notify('rmf_dismiss', { id });
    }

    /**
     * @param {string} id
     */
    primaryAction(id) {
        this.ntp.messaging.notify('rmf_primaryAction', { id });
    }

    /**
     * @param {string} id
     */
    secondaryAction(id) {
        this.ntp.messaging.notify('rmf_secondaryAction', { id });
    }
}
