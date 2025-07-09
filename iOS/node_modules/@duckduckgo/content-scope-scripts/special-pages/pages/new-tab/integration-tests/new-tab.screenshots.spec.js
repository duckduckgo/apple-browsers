import { expect, test } from '@playwright/test';
import { NewtabPage } from './new-tab.page.js';
import { ActivityPage } from '../app/activity/integration-tests/activity.page.js';
import { CustomizerPage } from '../app/customizer/integration-tests/customizer.page.js';
import { PrivacyStatsPage } from '../app/privacy-stats/integration-tests/privacy-stats.page.js';

const maxDiffPixels = 20;

test.describe('NTP screenshots', { tag: ['@screenshots'] }, () => {
    test.describe('feed = privacy stats', () => {
        test.use({ viewport: { width: 1000, height: 600 } });
        test('with dataset "few"', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const stats = new PrivacyStatsPage(page, ntp);
            await ntp.reducedMotion();

            // see privacy-stats.mocks.js
            await ntp.openPage({ additional: { stats: 'few' } });

            // make sure we're screenshotting when data is showing
            await stats.hasRows(4);
            await expect(page).toHaveScreenshot('stats-few.png', { maxDiffPixels });
        });
        test('with dataset "few" (dark)', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const stats = new PrivacyStatsPage(page, ntp);
            await ntp.reducedMotion();
            await ntp.darkMode();

            // see privacy-stats.mocks.js
            await ntp.openPage({ additional: { stats: 'few' } });

            // make sure we're screenshotting when data is showing
            await stats.hasRows(4);
            await expect(page).toHaveScreenshot('stats-few-dark.png', { maxDiffPixels });
        });
    });

    test.describe('activity widget screenshots narrow', () => {
        test.use({ viewport: { width: 800, height: 800 } });
        test('default', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const ap = new ActivityPage(page, ntp);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { 'protections.feed': 'activity' } });
            await ap.didRender();
            await expect(page).toHaveScreenshot('narrow-default.png', { maxDiffPixels });
        });
        test('empty', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const ap = new ActivityPage(page, ntp);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { 'protections.feed': 'activity', activity: 'empty' } });
            await ap.ready();
            await expect(page).toHaveScreenshot('narrow-empty.png', { maxDiffPixels });
        });
    });

    test.describe('activity widget screenshots wide', () => {
        test.use({ viewport: { width: 1000, height: 800 } });
        test('default', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const ap = new ActivityPage(page, ntp);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { 'protections.feed': 'activity' } });
            await ap.didRender();
            await expect(page).toHaveScreenshot('wide-default.png', { maxDiffPixels });
        });
        test('empty', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const ap = new ActivityPage(page, ntp);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { 'protections.feed': 'activity', activity: 'empty' } });
            await ap.ready();
            await expect(page).toHaveScreenshot('wide-empty.png', { maxDiffPixels });
        });
        test('with drawer', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const ap = new ActivityPage(page, ntp);
            const customizer = new CustomizerPage(ntp);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { 'protections.feed': 'activity' } });
            await ap.didRender();
            await customizer.opensCustomizer();
            await expect(page).toHaveScreenshot('wide-default-drawer.png', { maxDiffPixels });
        });
    });
});
