import { expect, test } from '@playwright/test';
import { HistoryTestPage } from './history.page.js';

const maxDiffPixels = 20;

test.describe('full history screenshots', { tag: ['@screenshots'] }, () => {
    test.use({ viewport: { width: 1080, height: 500 } });
    test('empty state', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(0);
        await hp.openPage();
        await hp.didMakeInitialQueries({ term: '' });
        await expect(page).toHaveScreenshot('full.empty.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(page).toHaveScreenshot('full.empty.dark.png', { maxDiffPixels });
    });
    test('short list (3 items)', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(3);
        await hp.openPage();
        await expect(page).toHaveScreenshot('full.short.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(page).toHaveScreenshot('full.short.dark.png', { maxDiffPixels });
    });
});

test.describe('history sidebar screenshots', { tag: ['@screenshots'] }, () => {
    test.use({ viewport: { width: 1080, height: 400 } });
    test('sidebar active/hover', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(3);
        await hp.openPage();
        await hp.selectsToday();
        await hp.hoversRange('yesterday');
        await expect(hp.sidebar()).toHaveScreenshot('sidebar.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.sidebar()).toHaveScreenshot('sidebar.dark.png', { maxDiffPixels });

        await hp.lightMode();
        await hp.hoversRangeDelete('yesterday');
        await expect(hp.sidebar()).toHaveScreenshot('sidebar.delete.light.png', { maxDiffPixels });

        await hp.darkMode();
        await expect(hp.sidebar()).toHaveScreenshot('sidebar.delete.dark.png', { maxDiffPixels });
    });
});

test.describe('history item selections', { tag: ['@screenshots'] }, () => {
    test.use({ viewport: { width: 1080, height: 400 } });
    test('main selecting', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.selectsRowIndex(1);
        await hp.selectsRowIndexWithShift(3);
        await hp.hoversRowIndex(1);
        await expect(hp.main()).toHaveScreenshot('main.select.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.main()).toHaveScreenshot('main.select.dark.png', { maxDiffPixels });
    });
    test('main hover', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.hoversRowIndex(0);
        await expect(hp.main()).toHaveScreenshot('main.hover.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.main()).toHaveScreenshot('main.hover.dark.png', { maxDiffPixels });
    });
    test('main selection + hover', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.selectsRowIndex(1);
        await hp.hoversRowIndexBtn(1);
        await expect(hp.main()).toHaveScreenshot('main.select+hover.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.main()).toHaveScreenshot('main.select+hover.dark.png', { maxDiffPixels });
    });
});

test.describe('history header', { tag: ['@screenshots'] }, () => {
    test.use({ viewport: { width: 1080, height: 400 } });
    test('idle header', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await expect(hp.header()).toHaveScreenshot('header.idle.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.header()).toHaveScreenshot('header.idle.dark.png', { maxDiffPixels });
    });
    test('search', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.types('example.com');
        await expect(hp.header()).toHaveScreenshot('header.search.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.header()).toHaveScreenshot('header.search.dark.png', { maxDiffPixels });
    });
    test('delete button', async ({ page }, workerInfo) => {
        const hp = HistoryTestPage.create(page, workerInfo).withEntries(12);
        await hp.openPage();
        await hp.didMakeNthQuery({ nth: 0, query: { term: '' }, source: 'initial' });
        await hp.hoversDeleteAllBtn();
        await expect(hp.header()).toHaveScreenshot('header.delete.light.png', { maxDiffPixels });
        await hp.darkMode();
        await expect(hp.header()).toHaveScreenshot('header.delete.dark.png', { maxDiffPixels });
    });
});
