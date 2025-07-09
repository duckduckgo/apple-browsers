/**
 * @typedef {import("../../types/new-tab.js").NextStepsData} NextStepsData
 * @typedef {import("../../types/new-tab.js").NextStepsConfig} NextStepsConfig
 */
import { Service } from '../service.js';

export class NextStepsService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @internal
     */
    constructor(ntp) {
        this.ntp = ntp;
        /** @type {Service<NextStepsData>} */
        this.dataService = new Service({
            initial: () => ntp.messaging.request('nextSteps_getData'),
            subscribe: (cb) => ntp.messaging.subscribe('nextSteps_onDataUpdate', cb),
        });

        /** @type {Service<NextStepsConfig>} */
        this.configService = new Service({
            initial: () => ntp.messaging.request('nextSteps_getConfig'),
            subscribe: (cb) => ntp.messaging.subscribe('nextSteps_onConfigUpdate', cb),
            persist: (data) => ntp.messaging.notify('nextSteps_setConfig', data),
        });
    }

    name() {
        return 'NextStepsService';
    }

    /**
     * @returns {Promise<{data: NextStepsData; config: NextStepsConfig}>}
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
     * @param {(evt: {data: NextStepsData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }

    /**
     * @param {(evt: {data: NextStepsConfig, source: 'manual' | 'subscription'}) => void} cb
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
     * Dismiss a particular card
     * @param {string} id
     */
    dismiss(id) {
        this.ntp.messaging.notify('nextSteps_dismiss', { id });
    }

    /**
     * Perform a primary action on a card
     * @param {string} id
     */
    action(id) {
        this.ntp.messaging.notify('nextSteps_action', { id });
    }
}
