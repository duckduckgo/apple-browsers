import { expect } from '@playwright/test';

/**
 * @typedef {import('../../../types/new-tab.js').NewTabMessages['subscriptions']['subscriptionEvent']} SubscriptionEventNames
 * @typedef {import('../../../types/new-tab.js').NewTabMessages['notifications']['method']} NotificationNames
 * @typedef {import('../../../types/new-tab.js').ProtectionsData} ProtectionsData
 */

const named = {
    /** @type {(n: NotificationNames) => NotificationNames} */
    notification: (n) => n,
    /** @type {(n: SubscriptionEventNames) => SubscriptionEventNames} */
    subscription: (n) => n,
};

export class ProtectionsPage {
    /**
     * @param {import("../../../integration-tests/new-tab.page.js").NewtabPage} ntp
     */
    constructor(ntp) {
        this.ntp = ntp;
        this.page = this.ntp.page;
    }

    context() {
        return this.page.locator('[data-entry-point="protections"]');
    }

    async ready() {
        await Promise.all([
            this.ntp.mocks.waitForCallCount({ method: 'protections_getConfig', count: 1 }),
            this.ntp.mocks.waitForCallCount({ method: 'protections_getData', count: 1 }),
        ]);
    }

    /**
     * @param {number} count
     */
    async receivesUpdatedTotal(count) {
        /** @type {ProtectionsData} */
        const data = {
            totalCount: count,
        };
        await this.ntp.mocks.simulateSubscriptionMessage(named.subscription('protections_onDataUpdate'), data);
        await expect(this.context().getByRole('heading', { level: 3 })).toContainText(`${count} tracking attempts blocked`);
    }

    async hasPolishText() {
        const heading = this.context().getByTestId('ProtectionsHeading');
        await expect(heading).toMatchAriaSnapshot(`
          - img "Privacy Shield"
          - heading "Raport ochrony" [level=2]
          - button "Ukryj ostatnią aktywność" [expanded] [pressed]:
            - img
          - heading /\\d+ – tyle prób śledzenia zablokowano/ [level=3]
          - paragraph: Ostatnie 7 dni
          `);
    }
}
