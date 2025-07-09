import { test } from '@playwright/test';
import { HistoryTestPage } from './history.page.js';

test.describe('history', () => {
    test('has empty state', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage();
        await hp.didMakeInitialQueries({ term: '' });
        await hp.hasEmptyState();
    });
    test('has no-results state', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage();
        await hp.didMakeInitialQueries({ term: '' });
        await hp.hasEmptyState();
        await hp.types('empty');
        await hp.hasNoResultsState();
    });
    test('makes an initial empty query', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage();
        await hp.didMakeInitialQueries({ term: '' });
    });
    test('makes an initial query with term', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage({ additional: { q: 'youtube' } });
        await hp.didMakeInitialQueries({ term: 'youtube' });
    });
    test('makes an initial query with range', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage({ additional: { range: 'today' } });
        await hp.didMakeInitialQueries({ range: 'today' });
    });
    test('switches from initial search query to range', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage({ additional: { q: 'youtube' } });
        await hp.didMakeInitialQueries({ term: 'youtube' });
        await hp.selectsToday();
        await hp.didMakeNthQuery({ nth: 1, query: { range: 'today' } });
    });
    test('switches from initial range to term', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage({ additional: { range: 'today' } });
        await hp.didMakeInitialQueries({ range: 'today' });
        await hp.types('youtube');
        await hp.didMakeNthQuery({ nth: 1, query: { term: 'youtube' } });
    });
    test('makes query after clearing input and retyping', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(100);
        await hp.openPage({ additional: { debounce: '10' } });

        // page load was an empty query
        await hp.didMakeInitialQueries({ term: '' });

        // then a manual entry
        await hp.types('youtube');
        await hp.didMakeNthQuery({ nth: 1, query: { term: 'youtube' } });

        // ensure the URL `q` params gets cleaned
        await hp.clearsInput();
        await page.waitForURL((url) => url.searchParams.get('q') === null, { timeout: 2000 });

        // clearing the input
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' } });

        // retyping a query
        await hp.types('playwright');
        await hp.didMakeNthQuery({ nth: 3, query: { term: 'playwright' } });
    });
    test('performs paging', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(300);
        await hp.openPage({});

        // from page load, empty query
        await hp.didMakeInitialQueries({ term: '' });

        // scroll to end, triggering the next fetch
        await hp.scrollsToEnd();

        // make sure the offset is sent
        await hp.didMakeNthPagingQuery({ nth: 1, query: { term: '' }, offset: 150 });

        // now search for something that has many results
        await hp.types('500');

        // and assert we're back at the top of the container
        await hp.didResetScroll();
    });
    test('selecting `all` resets to an empty query', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(300);
        await hp.openPage({});

        // start with a fresh range query
        await hp.selectsToday();
        await hp.didMakeNthQuery({ nth: 1, query: { range: 'today' } });

        // click 'all' (to reset)
        await hp.selectsAll();

        // ensure it's a full reset
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' } });
    });
    test('opening links', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(5);
        await hp.openPage({});
        await hp.opensLinks();
    });
    test('cannot delete "all" when there are no history items', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage({});
        await hp.didMakeInitialQueries({ term: '' });
        await hp.cannotDeleteAllFromSidebar();
    });
    test('re-issues an empty query when there are no history items', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage({});
        await hp.didMakeInitialQueries({ term: '' });
        await hp.selectsAll();
        await hp.didMakeNthQuery({ nth: 1, query: { term: '' } });
    });
    test('deleting range from sidebar i tems + resetting the query state', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.didMakeInitialQueries({ term: '' });

        await hp.selectsToday();
        await hp.didMakeNthQuery({ nth: 1, query: { range: 'today' } });

        await hp.deletesHistoryForToday({ action: 'delete' });
        await hp.sideBarItemWasRemoved('Show history for today');

        // makes a new query for default data
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' }, source: 'auto' });
    });
    test('deleting sidebar items, but dismissing modal', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.deletesHistoryForYesterday({ action: 'none' });
        await hp.sidebarHasItem('Show history for today');
    });
    test(
        'presses delete on range, but dismisses the modal',
        {
            annotation: {
                type: 'issue',
                description: 'https://app.asana.com/0/1201141132935289/1209501378934498',
            },
        },
        async ({ page }, workerInfo) => {
            const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
            await hp.openPage({});

            // simulate a modal appearing, but the user dismissing it
            await hp.deletesHistoryForYesterday({ action: 'none' });

            // this timeout is needed to simulate the bug - a small delay after closing the modal
            await page.waitForTimeout(100);

            // now check only the first query occurred (on page load)
            await hp.didMakeNQueries(1);
        },
    );
    test('deleting from the header', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.deletesAllHistoryFromHeader({ action: 'delete' });
    });
    test('deleting range from the header', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsToday();
        await hp.clicksDeleteAllInHeader({ action: 'delete' });
        await hp.didDeleteRange('today');
    });

    test('3 dots menu on history entry', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.menuForHistoryEntry(0, { action: 'delete' });
    });
    test('accepts domain search as param', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({ additional: { domain: 'youtube.com', urlDebounce: 0 } });
        await hp.didMakeInitialQueries({ domain: 'youtube.com' });
        await hp.inputContainsDomain('youtube.com');

        // now ensure it converts back to a query when typing
        await hp.types('autotrader');
        await hp.didMakeNthQuery({ nth: 1, query: { term: 'autotrader' } });
        await hp.didUpdateUrlWithQueryTerm('autotrader');
    });
    test('accepts domain search in response to context menu', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({ additional: { action: 'domain-search' } });
        await hp.menuForHistoryEntry(0, { action: 'domain-search' });
        await hp.didMakeNthQuery({ nth: 1, query: { domain: 'youtube.com' } });
    });
    test('deleting domain-search from the header', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({ additional: { action: 'domain-search' } });
        await hp.menuForHistoryEntry(0, { action: 'domain-search' });
        await hp.didMakeNthQuery({ nth: 1, query: { domain: 'youtube.com' } });
        await hp.clicksDeleteAllInHeader({ action: 'delete' });
        await hp.didDeleteDomain('youtube.com');

        // should have reset the UI now
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' }, source: 'auto' });
    });
    test('does not concatenate results if the query is not an addition', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(1);
        await hp.openPage({});
        await hp.selectsAll();
        await page.waitForTimeout(100);
        await hp.selectsAll();
        await page.waitForTimeout(100);
        await hp.selectsAll();
        await page.waitForTimeout(100);

        // assert no additional rows are present
        await hp.hasRowCount(1);

        // verify the queries still occurred, but they were not appended
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.didMakeNthQuery({ nth: 1, query: { term: '' } });
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' } });
        await hp.didMakeNthQuery({ nth: 3, query: { term: '' } });
    });
    test('search after pressing submit', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(200);
        await hp.openPage({});
        await hp.didMakeInitialQueries({ term: '' });
        await hp.types('café');
        await page.waitForURL((url) => url.searchParams.get('q') === 'café');
        await hp.didMakeNthQuery({ nth: 1, query: { term: 'café' } });
        await hp.submitSearchForm();
        await hp.didMakeNthQuery({ nth: 2, query: { term: 'café' } });
    });
    test.describe('default background colors', () => {
        test('default background light', async ({ page }, workerInfo) => {
            const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
            await hp.openPage();
            await hp.hasEmptyState();
            await hp.hasBackgroundColor({ hex: '#fafafa' });
        });
        test('default background dark', async ({ page }, workerInfo) => {
            const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
            await hp.darkMode();
            await hp.openPage();
            await hp.hasEmptyState();
            await hp.hasBackgroundColor({ hex: '#333333' });
        });
        test('with overrides from initial setup (light)', async ({ page }, workerInfo) => {
            const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
            await hp.openPage({ additional: { defaultStyles: 'visual-refresh' } });
            await hp.hasEmptyState();
            await hp.hasBackgroundColor({ hex: '#E9EBEC' });
        });
        test('with overrides from initial setup (dark)', async ({ page }, workerInfo) => {
            const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
            await hp.darkMode();
            await hp.openPage({ additional: { defaultStyles: 'visual-refresh' } });
            await hp.hasEmptyState();
            await hp.hasBackgroundColor({ hex: '#27282A' });
        });
    });
});
