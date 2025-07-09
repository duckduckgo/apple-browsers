import { perPlatform } from 'injected/integration-test/type-helpers.mjs';
import { Mocks } from '../../../shared/mocks.js';
import { expect } from '@playwright/test';
import { generateSampleData } from '../app/mocks/history.mocks.js';

/**
 * @typedef {import('injected/integration-test/type-helpers.mjs').Build} Build
 * @typedef {import('injected/integration-test/type-helpers.mjs').PlatformInfo} PlatformInfo
 */

export class HistoryTestPage {
    entries = 200;
    /**
     * Sets the number of entries stored in memory
     * @param {number} count - The number of entries to set.
     */
    withEntries(count) {
        this.entries = count;
        return this;
    }
    /**
     * @param {import("@playwright/test").Page} page
     * @param {Build} build
     * @param {PlatformInfo} platform
     */
    constructor(page, build, platform) {
        this.page = page;
        this.build = build;
        this.platform = platform;
        this.mocks = new Mocks(page, build, platform, {
            context: 'specialPages',
            featureName: 'history',
            env: 'development',
        });
        this.page.on('console', console.log);
        if (this.platform.name === 'extension') throw new Error('unreachable - not supported in extension platform');
        this.mocks.defaultResponses({
            /** @type {import('../types/history.ts').InitialSetupResponse} */
            initialSetup: {
                env: 'development',
                locale: 'en',
                platform: {
                    name: this.platform.name || 'windows',
                },
            },
        });
    }

    /**
     * Opens a page with optional parameters.
     * This method ensures that mocks are installed and routes are set up before navigating to the page.
     * @param {Object} [params] - Optional parameters for opening the page.
     * @param {'debug' | 'production'} [params.mode] - Optional parameters for opening the page.
     * @param {boolean} [params.willThrow] - Optional flag to simulate an exception
     * @param {Record<string, any>} [params.additional] - Optional map of key/values to add
     */
    async openPage({ mode = 'debug', additional, willThrow = false } = {}) {
        await this.mocks.install();
        const searchParams = new URLSearchParams({ mode, willThrow: String(willThrow) });
        for (const [key, value] of Object.entries(additional || {})) {
            searchParams.set(key, value);
        }

        searchParams.set('history', String(this.entries));

        // eslint-disable-next-line no-undef
        if (process.env.PAGE) {
            await this.page.goto('/' + '?' + searchParams.toString());
        } else {
            await this.page.goto('/history' + '?' + searchParams.toString());
        }
    }

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new HistoryTestPage(page, build, platformInfo);
    }

    async darkMode() {
        await this.page.emulateMedia({ colorScheme: 'dark' });
    }
    async lightMode() {
        await this.page.emulateMedia({ colorScheme: 'light' });
    }

    /**
     * @param {import('../types/history.ts').QueryKind} query
     */
    async didMakeInitialQueries(query) {
        const rangesCall = await this.mocks.waitForCallCount({ method: 'getRanges', count: 1 });
        const calls = await this.mocks.waitForCallCount({ method: 'query', count: 1 });
        expect(calls[0].payload.params).toStrictEqual(queryType({ query, limit: 150, offset: 0, source: 'initial' }));
        expect(rangesCall[0].payload.params).toStrictEqual({});
    }

    /**
     * @param {object} props
     * @param {number} props.nth
     * @param {import('../types/history.ts').QueryKind} props.query
     * @param {import('../types/history.ts').HistoryQuery['source']} [props.source='user']
     */
    async didMakeNthQuery({ nth, query, source = 'user' }) {
        const calls = await this.mocks.waitForCallCount({ method: 'query', count: nth + 1 });
        const params = calls[nth].payload.params;

        expect(params).toStrictEqual(queryType({ query, limit: 150, offset: 0, source }));
    }

    /**
     * @param {number} n
     */
    async didMakeNQueries(n) {
        const calls = await this.mocks.outgoing({ names: ['query'] });
        expect(calls).toHaveLength(n);
    }

    /**
     * @param {object} props
     * @param {number} props.nth
     * @param {import('../types/history.ts').QueryKind} props.query
     * @param {number} props.offset
     */
    async didMakeNthPagingQuery({ nth, query, offset }) {
        const calls = await this.mocks.waitForCallCount({ method: 'query', count: nth + 1 });
        const params = calls[nth].payload.params;

        expect(params).toStrictEqual(queryType({ query, limit: 150, offset, source: 'user' }));
    }

    async selectsToday() {
        const { page } = this;
        await page.getByLabel('Show history for today').click();
    }

    async selectsAll() {
        const { page } = this;
        await page.getByLabel('Show all history').click();
    }

    /**
     * @param {string} term
     */
    async types(term) {
        const { page } = this;
        await page.getByPlaceholder('Search').fill(term);
    }

    async clearsInput() {
        const { page } = this;
        await page.getByPlaceholder('Search').fill('');
    }

    async scrollsToEnd() {
        const { page } = this;
        await page.getByRole('main').evaluate(() => {
            const scrollableItem = document.querySelector('main');
            if (scrollableItem) {
                scrollableItem.scrollTop = scrollableItem.scrollHeight;
            }
        });
    }

    async didResetScroll() {
        const { page } = this;
        const scrollPosition = await page.waitForFunction(() => {
            const scrollableItem = document.querySelector('main');
            return scrollableItem ? scrollableItem.scrollTop === 0 : false;
        });
        expect(scrollPosition).toBeTruthy();
    }

    async opensLinks() {
        const row = this.main().locator('[aria-selected]').nth(0);
        await row.dblclick();
        await row.dblclick({ modifiers: ['Meta'] });
        await row.dblclick({ modifiers: ['Shift'] });

        await row.locator('a').click({ button: 'middle', force: true });
        await this._opensMainLink();
    }
    async _opensMainLink() {
        const calls = await this.mocks.waitForCallCount({ method: 'open', count: 3 });
        const url = 'https://www.youtube.com/watch?v=75Mw8r5gW8E';

        expect(calls[0].payload.params).toStrictEqual({
            url,
            target: 'same-tab',
        });

        expect(calls[1].payload.params).toStrictEqual({
            url,
            target: 'new-tab',
        });

        expect(calls[2].payload.params).toStrictEqual({
            url,
            target: 'new-window',
        });

        expect(calls[3].payload.params).toStrictEqual({
            url,
            target: 'new-tab',
        });
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async deletesHistoryForToday(resp = { action: 'delete' }) {
        const { page } = this;
        await page.getByLabel('Show history for today').hover();
        this._withDialogHandling(resp);
        await page.getByLabel('Delete history for today').click();
        const calls = await this.mocks.waitForCallCount({ method: 'deleteRange', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ range: 'today' });
    }

    async cannotDeleteAllFromSidebar() {
        if (this.entries !== 0) throw new Error('this test requires 0 entries');

        await this.sidebar().getByLabel('Show all history').hover();
        await this.sidebar().getByLabel('Delete all history').click({ force: true });

        await this.page.waitForTimeout(50);
        const count = await this.mocks.outgoing({ names: ['deleteRange'] });

        expect(count).toHaveLength(0);
    }

    /**
     * @param {import("../types/history.js").RangeId} range
     */
    async didDeleteRange(range) {
        const calls = await this.mocks.waitForCallCount({ method: 'deleteRange', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ range });
    }

    /**
     * @param {string} domain
     */
    async didDeleteDomain(domain) {
        const calls = await this.mocks.waitForCallCount({ method: 'deleteDomain', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ domain });
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async deletesHistoryForYesterday(resp = { action: 'delete' }) {
        const { page } = this;
        await page.getByLabel('Show history for yesterday').hover();
        this._withDialogHandling(resp);
        await page.getByLabel('Delete history for yesterday').click();
    }

    async sideBarItemWasRemoved(label) {
        const { page } = this;
        await expect(page.getByLabel(label)).not.toBeVisible({ timeout: 1000 });
    }

    async sidebarHasItem(label) {
        const { page } = this;
        await expect(page.getByLabel(label)).toBeVisible({ timeout: 1000 });
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async deletesAllHistoryFromHeader(resp) {
        const { page } = this;
        this._withDialogHandling(resp);
        await page.getByRole('button', { name: 'Delete All', exact: true }).click();
        const calls = await this.mocks.waitForCallCount({ method: 'deleteRange', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ range: 'all' });
        await this.hasEmptyState();
    }

    async hasEmptyState() {
        const { page } = this;
        await expect(page.getByRole('heading', { level: 2, name: 'Nothing to see here!' })).toBeVisible();
        await expect(page.getByText('No browsing history yet.')).toBeVisible();
    }

    async hasNoResultsState() {
        const { page } = this;
        await expect(page.getByRole('heading', { level: 2, name: 'No results found for "empty"' })).toBeVisible();
        await expect(page.getByText('Try searching for a different URL or keywords')).toBeVisible();
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async clicksDeleteInHeader(resp) {
        const { page } = this;
        this._withDialogHandling(resp);
        await page.locator('header').getByRole('button', { name: 'Delete', exact: true }).click();
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async clicksDeleteAllInHeader(resp) {
        const { page } = this;
        this._withDialogHandling(resp);
        await page.locator('header').getByRole('button', { name: 'Delete All', exact: true }).click();
    }

    /**
     * @param {number} nth - row index
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async menuForHistoryEntry(nth, resp) {
        const data = generateSampleData({ count: this.entries, offset: 0 });
        const nthItem = data[nth];
        await this.menuForMultipleHistoryEntries(nth, [nthItem.id], resp);
    }

    /**
     * @param {number} nth - row index to click the 3 dots on
     * @param {string[]} ids - expected ids
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async menuForMultipleHistoryEntries(nth, ids, resp) {
        const { page } = this;

        const cleanup = this._withDialogHandling(resp);
        // console.log(data[0].title);
        const data = generateSampleData({ count: this.entries, offset: 0 });
        const nthItem = data[nth];
        const row = this.main().locator(`[data-history-entry=${nthItem.id}]`);
        await row.hover();
        await page.locator(`[data-action="entries_menu"][value=${nthItem.id}]`).click();

        const calls = await this.mocks.waitForCallCount({ method: 'entries_menu', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ ids });
        cleanup();
    }

    /**
     * @param {number} nth
     */
    async selectsRowIndex(nth) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        const selected = page.locator('main').locator('[aria-selected="true"]');
        await rows.nth(nth).getByTestId('Item.domain').click();
        await expect(rows.nth(nth)).toHaveAttribute('aria-selected', 'true');
        await expect(selected).toHaveCount(1);
    }

    /**
     * @param {number} nth
     */
    async hoversRowIndex(nth) {
        const rows = this.page.locator('main').locator('[aria-selected]');
        await rows.nth(nth).hover();
        await rows.nth(nth).locator('[data-action="entries_menu"]').waitFor({ state: 'visible' });
    }
    /**
     * @param {number} nth
     */
    async hoversRowIndexBtn(nth) {
        const rows = this.page.locator('main').locator('[aria-selected]');
        await rows.nth(nth).locator('[data-action="entries_menu"]').hover();
    }
    /**
     *
     */
    async hoversDeleteAllBtn() {
        await this.page.getByRole('button', { name: 'Delete All', exact: true }).hover();
    }

    /**
     * @param {number} nth
     */
    async rowIsSelected(nth) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        await expect(rows.nth(nth)).toHaveAttribute('aria-selected', 'true');
    }

    /**
     * @param {number} nth
     */
    async rowIsNotSelected(nth) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        await expect(rows.nth(nth)).toHaveAttribute('aria-selected', 'false');
    }

    /**
     * @param {number} nth
     */
    async selectsRowWithCtrl(nth) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        await rows
            .nth(nth)
            .getByTestId('Item.domain')
            .click({ modifiers: ['Meta'] });
    }
    /**
     * @param {number} nth
     */
    async selectsRowIndexWithShift(nth) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        await rows
            .nth(nth)
            .getByTestId('Item.domain')
            .click({ modifiers: ['Shift'] });
    }

    /**
     * @param {number} count
     */
    ids(count) {
        return generateSampleData({ count: this.entries, offset: 0 })
            .slice(0, count)
            .map((x) => x.id);
    }

    /**
     * @param {number} nth
     * @param {string[]} expectedIds
     */
    async rightClicksWithinSelection(nth, expectedIds) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        const selectedRow = rows.nth(nth);
        await selectedRow.click({ button: 'right' });
        const calls = await this.mocks.waitForCallCount({ method: 'entries_menu', count: 1 });

        expect(calls[0].payload.params).toStrictEqual({ ids: expectedIds });
    }

    async cannotDeleteAllWhenEmpty() {
        const { page } = this;
        await expect(page.getByRole('button', { name: 'Delete All', exact: true })).toHaveAttribute('aria-disabled', 'true');
    }

    async deletesSelection() {
        const { page } = this;
        await page.locator('header').getByRole('button', { name: 'Delete', exact: true }).click();
    }

    async deletesAll() {
        const { page } = this;
        await page.locator('header').getByRole('button', { name: 'Delete All', exact: true }).click();
    }

    /**
     * @param {string} term
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async deletesAllForTerm(term, resp) {
        this._withDialogHandling(resp);
        await this.deletesAll();
        const calls = await this.mocks.waitForCallCount({ method: 'deleteTerm', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ term });
    }

    async pressesEscape() {
        const { page } = this;
        const main = page.locator('body');
        await main.press('Escape');
    }

    /**
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    _withDialogHandling(resp) {
        const { page } = this;

        const handler = (dialog) => {
            if (resp.action === 'delete' || resp.action === 'domain-search') {
                return dialog.accept();
            } else {
                return dialog.dismiss();
            }
        };
        page.on('dialog', handler);
        return () => {
            page.off('dialog', handler);
        };
    }

    /**
     * @param {string[]} ids
     * @param {import('../types/history.ts').DeleteRangeResponse} resp
     */
    async deletesWithKeyboard(ids, resp) {
        const { page } = this;
        this._withDialogHandling(resp);

        // Simulate pressing the 'Delete' key
        await page.keyboard.press('Delete');

        const calls = await this.mocks.waitForCallCount({ method: 'entries_delete', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ ids });

        for (const id of ids) {
            await expect(page.locator(`main [aria-selected] button[value=${id}]`)).not.toBeVisible();
        }
    }

    /**
     * @param {string} domain
     */
    async inputContainsDomain(domain) {
        const { page } = this;
        await expect(page.getByPlaceholder('Search')).toHaveValue(domain);
    }

    /**
     * @param {string} term
     */
    async didUpdateUrlWithQueryTerm(term) {
        const { page } = this;
        await page.waitForURL((url) => url.searchParams.get('q') === term);
    }

    /**
     * @param {number} count
     */
    async hasRowCount(count) {
        const { page } = this;
        const rows = page.locator('main').locator('[aria-selected]');
        const rowCount = await rows.count();
        expect(rowCount).toBe(count);
    }

    /**
     * @param {number} count
     */
    async waitForRowCount(count) {
        const { page } = this;
        await page.waitForFunction((count) => document.querySelector('main')?.querySelectorAll('[aria-selected]').length === count, count);
    }

    sidebar() {
        return this.page.locator('aside');
    }

    main() {
        return this.page.locator('main');
    }
    header() {
        return this.page.locator('header');
    }

    async hoversRange(range) {
        await this.page.getByLabel(`Show history for ${range}`).hover();
    }
    async hoversRangeDelete(range) {
        // await this.page.pause();
        await this.page.getByRole('button', { name: `Delete history for ${range}` }).hover();
    }

    /**
     * @param {number[]} indexes
     */
    async didDeleteSelection(indexes) {
        const items = generateSampleData({ count: this.entries, offset: 0 });
        const ids = indexes.map((index) => items[index].id);
        const calls = await this.mocks.waitForCallCount({ method: 'entries_delete', count: 1 });
        expect(calls[0].payload.params).toStrictEqual({ ids });
    }

    async didNotDelete() {
        const calls = await this.mocks.outgoing({ names: ['entries_delete'] });
        expect(calls).toHaveLength(0);
    }

    async submitSearchForm() {
        await this.page.getByRole('searchbox', { name: 'Search your history' }).press('Enter');
    }

    async clicksOutsideOfRows() {
        await this.page.getByRole('main').click({ position: { x: 0, y: 0 } });
    }

    async selectedRowCountIs(number) {
        await expect(this.main().locator('[aria-selected="true"]')).toHaveCount(number);
    }

    /**
     * @param {object} params
     * @param {string} params.hex
     * @returns {Promise<void>}
     */
    async hasBackgroundColor({ hex }) {
        const r = parseInt(hex.slice(1, 3), 16);
        const g = parseInt(hex.slice(3, 5), 16);
        const b = parseInt(hex.slice(5, 7), 16);
        const rgb = `rgb(${[r, g, b].join(', ')})`;
        await expect(this.page.locator('[data-layout-mode="normal"]')).toHaveCSS('background-color', rgb, { timeout: 50 });
    }
}

/**
 * @param {import('../types/history.ts').HistoryQuery} q
 * @return {import('../types/history.ts').HistoryQuery}
 */
function queryType(q) {
    return q;
}
