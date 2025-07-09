import { expect } from '@playwright/test';
import { gen } from '../mocks/favorites.data.js';

export class FavoritesPage {
    static ENTRY_POINT = '[data-entry-point="favorites"]';
    /**
     * @param {import("../../../integration-tests/new-tab.page.js").NewtabPage} ntp
     */
    constructor(ntp) {
        this.ntp = ntp;
    }

    async togglesExpansion() {
        const { page } = this.ntp;
        await this.showMore();
        await expect(page.getByLabel('Add Favorite')).toBeVisible();
        await page.getByLabel('Show less').click();
        await expect(page.getByLabel('Add Favorite')).not.toBeVisible();
    }

    async opensInNewTab() {
        await this.nthFavorite(0).click({ modifiers: ['Meta'] });
        await this.nthFavorite(0).click({ button: 'middle' });
        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_open', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ id: 'id-many-1', url: 'https://example.com/?id=id-many-1', target: 'new-tab' });
        expect(calls[1].payload.params).toStrictEqual({ id: 'id-many-1', url: 'https://example.com/?id=id-many-1', target: 'new-tab' });
    }

    async opensInNewWindow() {
        await this.nthFavorite(0).click({ modifiers: ['Shift'] });
        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_open', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ id: 'id-many-1', url: 'https://example.com/?id=id-many-1', target: 'new-window' });
    }

    async opensInSameTab() {
        await this.nthFavorite(0).click();
        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_open', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ id: 'id-many-1', url: 'https://example.com/?id=id-many-1', target: 'same-tab' });
    }

    async addsAnItem() {
        const { page } = this.ntp;
        await this.showMore();
        await page.getByLabel('Add Favorite').click();
        await this.ntp.mocks.waitForCallCount({ method: 'favorites_add', count: 1 });
    }

    /**
     * @param {number|string} count
     */
    async showMore(count = '10') {
        const { page } = this.ntp;
        await page.locator(FavoritesPage.ENTRY_POINT).getByLabel(`Show more (${count} remaining)`).click();
    }

    async rightClickInvokesContextMenuFor() {
        const first = this.nthFavorite(0);
        const second = this.nthFavorite(1);
        const [id, id2] = await Promise.all([first.getAttribute('data-id'), second.getAttribute('data-id')]);
        await first.click({ button: 'right' });
        await second.click({ button: 'right' });
        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_openContextMenu', count: 2 });
        expect(calls[0].payload).toStrictEqual({
            context: 'specialPages',
            featureName: 'newTabPage',
            method: 'favorites_openContextMenu',
            params: { id },
        });
        expect(calls[1].payload).toStrictEqual({
            context: 'specialPages',
            featureName: 'newTabPage',
            method: 'favorites_openContextMenu',
            params: { id: id2 },
        });
    }

    async tabsThroughItems() {
        const { page } = this.ntp;

        const context = page.getByTestId('FavoritesConfigured');
        await context.press('Tab');
        const firstTile = context.locator('a[href^="https:"][data-id]').nth(0);
        const secondTile = context.locator('a[href^="https:"][data-id]').nth(1);
        const isActiveElement = await firstTile.evaluate((elem) => elem === document.activeElement);

        expect(isActiveElement).toBe(true);

        {
            // second
            await context.press('Tab');
            const isActiveElement = await secondTile.evaluate((elem) => elem === document.activeElement);
            expect(isActiveElement).toBe(true);
        }

        // 3rd
        await context.press('Tab');
        // 4th
        await context.press('Tab');
        // 5th
        await context.press('Tab');
        // 6th
        await context.press('Tab');
        // 7th - should be the 'show more' toggle now
        await context.press('Tab');

        {
            const button = page.getByLabel('Show more (10 remaining)');
            const isActiveElement = await button.evaluate((elem) => elem === document.activeElement);
            expect(isActiveElement).toBe(true);
        }

        await context.press('Space');
        await this.waitForNumFavorites(16);
        await context.press('Space');
        await this.waitForNumFavorites(6);
    }

    /**
     * Drags a favorite item from one position to another on the page.
     *
     * @param {object} options - The drag options.
     * @param {number} options.index - The index of the favorite item to be dragged.
     * @param {number} options.to - The index where the favorite item should be dragged to.
     * @returns {Promise<{ id: string }>}
     */
    async drags({ index, to }) {
        const { page } = this.ntp;

        const source = this.nthFavorite(index);
        const target = this.nthFavorite(to);

        // read the id of the thing we'll drag so we can compare with the payload
        const id = await source.getAttribute('data-id');
        if (!id) throw new Error('unreachable!, must have id');
        const href = await source.getAttribute('href');
        if (!id) throw new Error('unreachable, must have href');

        // capture the drag data
        await page.evaluate(() => {
            document.addEventListener('dragstart', (event) => {
                const dataTransfer = event.dataTransfer;
                const url = dataTransfer?.getData('text/plain');
                const data = dataTransfer?.getData('application/vnd.duckduckgo.bookmark-by-id');

                if (url && data) {
                    /** @type {any} */ (window).__dragdata ??= [];
                    /** @type {any} */ (window).__dragdata.push(url, data);
                } else {
                    throw new Error('missing text/plain or application/vnd.duckduckgo.bookmark-by-id');
                }
            });
        });

        /**
         * ⚠️⚠️⚠️ NOTE ⚠️⚠️⚠️
         * the `targetPosition` here needs to be over HALF of the icon width, since
         * the drag and drop implementation drops into the gaps between icons.
         *
         * So, when we want to drag index 0 to index 2, we have to get to the third element, but cross
         * over half-way.
         */
        await source.dragTo(target, { targetPosition: { x: 50, y: 50 } });

        // verify drag data
        const dragData = await page.evaluate(() => /** @type {any} */ (window).__dragdata);
        expect(dragData).toStrictEqual([href, id]);

        return { id };
    }

    async sent({ id, fromIndex, targetIndex }) {
        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_move', count: 1 });
        expect(calls[0].payload).toStrictEqual({
            context: 'specialPages',
            featureName: 'newTabPage',
            method: 'favorites_move',
            params: { id, fromIndex, targetIndex },
        });
    }

    async dragsExternal() {}

    /**
     * @param {number} number
     */
    async waitForNumFavorites(number) {
        const { page } = this.ntp;
        await page.waitForFunction(
            (count) => {
                const collection = document.querySelectorAll('[data-testid="FavoritesConfigured"] a[href^="https:"][data-id]');
                return collection.length === count;
            },
            number,
            { timeout: 2000 },
        );
    }

    async tabsPastEmptyFavorites() {
        const { page } = this.ntp;
        const body = page.locator('body');
        await body.press('Tab');
        await body.press('Tab');
        const statsToggle = page.getByLabel('Hide recent activity');
        await expect(statsToggle).toBeFocused();
    }

    /**
     * Retrieves the nth favorite item from the Favorites section on the current page.
     *
     * @param {number} n - The index of the favorite item to retrieve (starting from 0).
     * @return {import("@playwright/test").Locator}
     */
    nthFavorite(n) {
        const { page } = this.ntp;
        const context = page.getByTestId('FavoritesConfigured');
        return context.locator('[data-drop-target-for-element="true"]').nth(n);
    }

    /**
     * Retrieves the nth favorite item from the Favorites section on the current page.
     *
     * @param {number} n - The index of the favorite item to retrieve (starting from 0).
     * @return {import("@playwright/test").Locator}
     */
    nthExternalDropTarget(n) {
        const { page } = this.ntp;
        const context = page.getByTestId('FavoritesConfigured');
        return context.locator('[data-drop-target-for-external="true"]').nth(n);
    }

    async requestsSmallFavicon() {
        const first = this.nthFavorite(0);
        const src = await first.locator('img').getAttribute('src');
        expect(src).toBe('./icons/favicon@2x.png?preferredSize=16');
    }

    /**
     * @param {() => Promise<void>} setup
     */
    async hasFallbackIcons(setup) {
        const { page } = this.ntp;

        // watch for the fallback icon response
        const req = page.waitForResponse((res) => res.url().endsWith('other.svg'));

        // load the page
        await setup();

        // wait for the image to be loaded
        await req;

        // grab all the styles of the fallback icons
        const wrapper = page.locator('[data-entry-point="favorites"]');
        const letterFallbacks = await wrapper.evaluate((wrapper) => {
            const icons = wrapper.querySelectorAll('[data-state="using_fallback_text"]');
            return Array.from(icons).map((/** @type {HTMLElement} */ icon) => icon.style?.backgroundColor);
        });

        // These are known to be correct, and exist here to prevent accidental changes
        // see the `fallbacks` sample data in `favorites.data.js`
        // prettier-ignore
        expect(letterFallbacks).toStrictEqual([
            "rgb(231, 165, 56)",
            "rgb(153, 219, 122)",
            "rgb(107, 180, 239)"
        ]);

        // grab the fallback image from the grid. This will fail if there's more than 1
        const imgFallback = await wrapper.locator('[data-state="did_load_fallback_img"]').getAttribute('src');
        expect(imgFallback?.endsWith('other.svg')).toBe(true);
    }

    /**
     * Accepts an external drop at a specified index on the page.
     *
     * @param {Object} param
     * @param {number} param.index - The index of the element where the drop will occur.
     */
    async acceptsExternalDrop({ index }) {
        const { page } = this.ntp;
        const handle = await this.nthExternalDropTarget(index).elementHandle();

        await page.evaluate((target) => {
            function createDragEvent(type) {
                const event = new DragEvent(type, {
                    bubbles: true,
                    cancelable: true,
                    dataTransfer: new DataTransfer(),
                });
                event.dataTransfer?.setData('text/html', '<meta name="application/vnd.duckduckgo.bookmark-by-id" content="3" />');
                return event;
            }

            // Dispatch the dragenter and dragover events to simulate the drag start
            target?.dispatchEvent(createDragEvent('dragenter'));
            target?.dispatchEvent(createDragEvent('dragover'));
            target?.dispatchEvent(createDragEvent('drop'));
        }, handle);

        const calls = await this.ntp.mocks.waitForCallCount({ method: 'favorites_move', count: 1 });
        expect(calls[0].payload).toStrictEqual({
            context: 'specialPages',
            featureName: 'newTabPage',
            method: 'favorites_move',
            params: {
                id: '3',
                targetIndex: index,
                fromIndex: 16, // this is the length of the list, and it gets dropped at the end in the test.
            },
        });
    }

    async scrollToContainer() {
        const { page } = this.ntp;
        const rect = await page.locator(FavoritesPage.ENTRY_POINT).evaluate((e) => e.getBoundingClientRect());
        // scroll to the top of the container
        await page.evaluate((y) => window.scrollBy(0, y), rect.top);

        // give chance for any DOM changes to occur
        await page.waitForTimeout(500);
    }

    /**
     * @param {number} from
     * @param {number} to
     */
    async favoriteWasRemoved(from, to) {
        const { page } = this.ntp;

        // verify the DOM is in the expected state first
        await expect(page.getByTestId('FavoritesConfigured').locator('a[href]')).toHaveCount(from);

        const fourItems = gen(to);

        // deliver the update
        await this.ntp.mocks.simulateSubscriptionMessage('favorites_onDataUpdate', fourItems);

        // verify the DOM is updated
        await expect(page.getByTestId('FavoritesConfigured').locator('a[href]')).toHaveCount(to);
    }

    /**
     * Simulate getting entirely fresh data
     */
    async receivesNewDataAndShowsAll(count) {
        const { page } = this.ntp;

        const items = gen(count);
        await this.ntp.mocks.simulateSubscriptionMessage('favorites_onDataUpdate', items);

        // The bug occurred after a debounced timer, so this timer reproduces it
        await page.waitForTimeout(100);

        // Every tile should be shown
        await this.waitForNumFavorites(count);
    }

    async receivesRefresh() {
        await this.ntp.mocks.simulateSubscriptionMessage('favorites_onRefresh', { items: [{ kind: 'favicons' }] });
    }
}
