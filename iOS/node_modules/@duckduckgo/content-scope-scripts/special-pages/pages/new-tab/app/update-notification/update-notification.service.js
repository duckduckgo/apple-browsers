/**
 * @typedef {import("../../types/new-tab.js").UpdateNotificationData} UpdateNotificationData
 */
import { Service } from '../service.js';

/**
 * @document ./update-notification.service.md
 */

export class UpdateNotificationService {
    /**
     * @param {import("../../src/index.js").NewTabPage} ntp - The internal data feed, expected to have a `subscribe` method.
     * @param {UpdateNotificationData} initial
     * @internal
     */
    constructor(ntp, initial) {
        this.ntp = ntp;
        /** @type {Service<UpdateNotificationData>} */
        this.dataService = new Service(
            {
                subscribe: (cb) => ntp.messaging.subscribe('updateNotification_onDataUpdate', cb),
            },
            initial,
        );
    }

    /**
     * @internal
     */
    destroy() {
        this.dataService.destroy();
    }

    /**
     * @param {(evt: {data: UpdateNotificationData, source: 'manual' | 'subscription'}) => void} cb
     * @internal
     */
    onData(cb) {
        return this.dataService.onData(cb);
    }

    /**
     * @internal
     */
    dismiss() {
        this.ntp.messaging.notify('updateNotification_dismiss');

        this.dataService.update((_old) => {
            return { content: null };
        });
    }
}
