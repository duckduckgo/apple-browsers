import { test } from '@playwright/test';
import { HistoryTestPage } from './history.page.js';

test.describe('history selections', () => {
    test('selects one item at a time', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndex(1);
        await hp.selectsRowIndex(2);
    });
    test('resets selection with new query', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.types('example.com');
        await hp.rowIsNotSelected(0);
    });
    test('adds to selection', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});

        await hp.selectsRowIndex(0);
        await hp.selectsRowWithCtrl(1);

        await hp.rowIsSelected(0);
        await hp.rowIsSelected(1);
    });
    test('removes from a selection', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});

        await hp.selectsRowIndex(0);
        await hp.selectsRowWithCtrl(1);
        await hp.selectsRowWithCtrl(1);
        await hp.rowIsSelected(0);
        await hp.rowIsNotSelected(1);
    });
    test('Expands a select with shift+click', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(4);
        await hp.rowIsSelected(0);
        await hp.rowIsSelected(1);
        await hp.rowIsSelected(2);
        await hp.rowIsSelected(3);
        await hp.rowIsSelected(4);

        // control
        await hp.rowIsNotSelected(5);
    });
    test('Anchors a selection with shift+click', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(4);
        await hp.selectsRowIndexWithShift(6);
        await hp.rowIsSelected(4);
        await hp.rowIsSelected(5);
        await hp.rowIsSelected(6);

        await hp.selectsRowIndexWithShift(0);
        await hp.rowIsSelected(0);
        await hp.rowIsSelected(1);
        await hp.rowIsSelected(2);
        await hp.rowIsSelected(3);
        await hp.rowIsSelected(4);

        // control
        await hp.rowIsNotSelected(5);
        await hp.rowIsNotSelected(6);
    });
    test('removes all selections when any item is deleted', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.menuForHistoryEntry(1, { action: 'delete' });
        await hp.rowIsNotSelected(0);
    });
    test('issues context menu for selected group', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(2);
        await hp.rightClicksWithinSelection(0, hp.ids(3));
    });
    test('when multiple selected, issues context menu for a single row, when a non-selected item is the target', async ({
        page,
    }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(2);

        // control
        await hp.rowIsSelected(0);
        await hp.rowIsSelected(1);
        await hp.rowIsSelected(2);

        // do the action, right-clicking an entry outside of the selection
        await hp.menuForHistoryEntry(3, { action: 'delete' });

        // double-check
        await hp.rowIsNotSelected(0);
    });
    test('expands selection up/down with shift+arrows', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await page.locator('main').press('Shift+ArrowDown');
        await page.locator('main').press('Shift+ArrowDown');

        // control, making sure the element became selected
        await hp.rowIsSelected(0);
        await hp.rowIsSelected(1);
        await hp.rowIsSelected(2);

        // now go bac kup
        await page.locator('main').press('Shift+ArrowUp');
        await page.locator('main').press('Shift+ArrowUp');

        // only the first should be selected now
        await hp.rowIsSelected(0);
        await hp.rowIsNotSelected(1);
        await hp.rowIsNotSelected(2);
    });
    test('`deleteAll` does nothing in the empty state', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage({});
        await hp.cannotDeleteAllWhenEmpty();
    });
    test('`deleteAll` button text changes to `delete` when selections are made', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.deletesSelection();
    });
    test('`delete` in header respects selection', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.clicksDeleteInHeader({ action: 'delete' });
        await hp.didDeleteSelection([0]);
    });
    test('`delete` in header respects selection after search', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.types('2');
        await hp.waitForRowCount(2);
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(1);
        await hp.clicksDeleteInHeader({ action: 'delete' });
        await hp.didDeleteSelection([0, 1]);
    });
    test('`deleteAll` during search (no selections)', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });

        // do the search
        await hp.types('example.com');
        await hp.didMakeNthQuery({ nth: 1, query: { term: 'example.com' } });

        // delete for the given term
        await hp.deletesAllForTerm('example.com', { action: 'delete' });

        // should have reset the UI now
        await hp.didMakeNthQuery({ nth: 2, query: { term: '' }, source: 'auto' });
    });
    test('removes all selections with ESC key', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.pressesEscape();
        await hp.rowIsNotSelected(0);
    });
    test('deletes a single row item without confirmation', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.deletesWithKeyboard(hp.ids(1), { action: 'delete' });
    });
    test('does not delete item when backspace is pressed in search', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2);
        await hp.openPage({});
        await hp.types('youtube.com');
        await hp.selectsRowIndex(0);
        await page.locator('input[type="search"]').press('Delete');
        await page.waitForTimeout(50);
        await hp.didNotDelete();
    });
    test('deletes multiple rows with confirmation', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(2);
        await hp.deletesWithKeyboard(hp.ids(3), { action: 'delete' });
    });
    test('3 dots menu on multiple history entries', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.selectsRowIndexWithShift(2);
        await hp.menuForMultipleHistoryEntries(0, hp.ids(3), { action: 'delete' });
    });
    test('clicking outside of rows de-selects everything', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(2000);
        await hp.openPage({});
        await hp.selectsRowIndex(0);
        await hp.clicksOutsideOfRows();
        await hp.selectedRowCountIs(0);
    });
});
