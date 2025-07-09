import { generateSampleData } from '../mocks/activity.mock-transport.js';
import { expect } from '@playwright/test';

/**
 * @typedef {import('../../../types/new-tab.js').NewTabMessages['subscriptions']['subscriptionEvent']} SubscriptionEventNames
 * @typedef {import('../../../types/new-tab.js').ActivityOnDataPatchSubscription['params']} PatchParams
 */

/**
 * @param {SubscriptionEventNames} n
 */
const sub = (n) => n;

export class BatchingPage {
    /**
     * @param {import('@playwright/test').Page} page
     * @param {import('../../../integration-tests/new-tab.page.js').NewtabPage} ntp
     * @param {import("./activity.page.js").ActivityPage} ap
     */
    constructor(page, ntp, ap) {
        this.page = page;
        this.ntp = ntp;
        this.ap = ap;
    }

    async fetchedRows(count) {
        const data = generateSampleData(200);
        const ids = data.slice(0, count).map((x) => x.url);

        await this.ntp.mocks.waitForCallCount({ method: 'activity_getUrls', count: 1 });
        const calls2 = await this.ntp.mocks.waitForCallCount({ method: 'activity_getDataForUrls', count: 1 });
        expect(calls2[0].payload.params.urls).toStrictEqual(ids);
    }

    async triggerNext() {
        const { page } = this;

        await page.evaluate(() => {
            const scrollableItem = document.querySelector('[data-main-scroller]');
            if (scrollableItem) {
                scrollableItem.scrollTop = scrollableItem.scrollHeight;
            }
        });
    }

    async acceptsUpdate(nth) {
        const data = generateSampleData(200);
        const original = structuredClone(data[nth]);
        const clone1 = structuredClone(data[nth]);
        clone1.history.push({ url: 'https://update.', title: 'test update 1', relativeTime: 'Just now' });

        /** @type {import('../../../types/new-tab.js').ActivityOnDataPatchSubscription['params']} */
        const patch = {
            patch: clone1,
            urls: data.map((x) => x.url),
            totalTrackersBlocked: 0,
        };

        const locator = this.ap.context().getByTestId('ActivityItem').nth(nth);

        // deliver the update
        await this.ntp.mocks.simulateSubscriptionMessage(sub('activity_onDataPatch'), patch);

        // this item should now have an expander
        await locator.getByLabel('Show 1 more').click();

        // now assert the history item is shown
        await expect(locator).toMatchAriaSnapshot(`
        - list:
          - listitem:
            - link "(h) 0.0 - ARizGXo5MduB"
            - text: 5 minutes ago
          - listitem:
            - link "(h) 0.1 - BSj0HYp6NevC"
            - text: 3 weeks ago
          - listitem:
            - link "test update 1"
            - text: Just now
            - button "Hide additional":
              - img`);

        /** @type {import('../../../types/new-tab.js').ActivityOnDataPatchSubscription['params']} */
        const patch2 = {
            patch: original,
            urls: data.map((x) => x.url),
            totalTrackersBlocked: 0,
        };

        // deliver the update
        await this.ntp.mocks.simulateSubscriptionMessage(sub('activity_onDataPatch'), patch2);

        // now assert only 2 history items show
        await expect(locator).toMatchAriaSnapshot(`
        - list:
          - listitem:
            - link "(h) 0.0 - ARizGXo5MduB"
            - text: 5 minutes ago
          - listitem:
            - link "(h) 0.1 - BSj0HYp6NevC"
            - text: 3 weeks ago`);
    }

    /**
     * Removes an item from a generated sample data array at the specified index and sends updated data
     * through a simulated subscription message.
     *
     * @param {number} index - The index of the item to remove from the sample data array.
     */
    async itemRemovedViaPatch(index) {
        const data = generateSampleData(this.ap.entries);
        data.splice(index, 1);
        const update = toPatch(data);
        await this.ntp.mocks.simulateSubscriptionMessage(sub('activity_onDataPatch'), update);
    }

    /**
     * Simulates removing all items
     * @param {object} params
     * @param {number} params.index - The index of the item to remove from the sample data array.
     * @param {number} params.nextTrackerCount
     */
    async removesItem({ index, nextTrackerCount }) {
        const { page } = this;
        await page.locator('button[data-action="remove"]').nth(index).click();

        const update = toPatch([]);
        update.totalTrackersBlocked = nextTrackerCount;
        await this.ntp.mocks.simulateSubscriptionMessage(sub('activity_onDataPatch'), update);
    }

    async fillsHoleWhenItemRemoved() {
        if (this.ap.entries !== 6) throw new Error('this scenario expects 6 initial items');

        // control, these calls already happened on page load
        await this.ntp.mocks.waitForCallCount({ method: 'activity_getUrls', count: 1 });
        const first = await this.ntp.mocks.waitForCallCount({ method: 'activity_getDataForUrls', count: 1 });

        expect(first[0].payload.params).toStrictEqual({
            urls: [
                'https://0.ARizGXo5Md.com',
                'https://1.BSj0HYp6Ne.com',
                'https://2.CTk1IZq7Of.com',
                'https://3.DUl2Jar8Pg.com',
                'https://4.EVm3Kbs9Qh.com',
            ],
        });

        // now remove the first item via subscription
        await this.itemRemovedViaPatch(0);

        // now there must have been 2 calls
        const [, second] = await this.ntp.mocks.waitForCallCount({ method: 'activity_getDataForUrls', count: 2 });

        expect(second.payload.params).toStrictEqual({
            urls: ['https://5.FWn4LctARi.com'],
        });
    }

    async itemsReorder() {
        if (this.ap.entries !== 6) throw new Error('this scenario expects 6 initial items');

        await this.ap.hasRows(5);

        // control: this is the initial state
        await expect(this.ap.context()).toMatchAriaSnapshot(`
        - list:
          - listitem:
            - link "0 ARizGXo5Md"
          - listitem:
            - link "1 BSj0HYp6Ne"
          - listitem:
            - link "2 CTk1IZq7Of"
          - listitem:
            - link "3 DUl2Jar8Pg"
          - listitem:
            - link "4 EVm3Kbs9Qh"
        `);

        const data = generateSampleData(this.ap.entries);
        const first = data[0];
        const last = data[data.length - 1];

        data[0] = last;
        data[data.length - 1] = first;

        const patch = toPatch(data);
        await this.ntp.mocks.simulateSubscriptionMessage(sub('activity_onDataPatch'), patch);

        // Ensure the
        await expect(this.ap.context()).toMatchAriaSnapshot(`
        - list:
          - listitem:
            - link "5 FWn4LctARi"
          - listitem:
            - link "1 BSj0HYp6Ne"
          - listitem:
            - link "2 CTk1IZq7Of"
          - listitem:
            - link "3 DUl2Jar8Pg"
          - listitem:
            - link "4 EVm3Kbs9Qh"
        `);
    }

    async displaysTrackerCount() {
        if (this.ap.entries !== 6) throw new Error('this scenario expects 6 initial items');

        const { totalTrackersBlocked } = toPatch(generateSampleData(this.ap.entries));

        // ensure the total is shown, even though some item will not have been fetched
        await expect(this.ap.context().getByRole('heading')).toContainText(`${totalTrackersBlocked} tracking attempts blocked`);
    }
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
