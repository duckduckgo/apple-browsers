import { expect, test } from '@playwright/test';
import { ProtectionsPage } from './protections.page.js';
import { NewtabPage } from '../../../integration-tests/new-tab.page.js';

const maxDiffPixels = 20;

test.describe('Protections screenshots', { tag: ['@screenshots'] }, () => {
    test.describe('privacy stats', () => {
        test('with data', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            const protections = new ProtectionsPage(ntp);
            await ntp.openPage({ additional: { 'protections.feed': 'privacy-stats' } });
            await protections.ready();

            await expect(protections.context()).toHaveScreenshot('protections-stats.png', { maxDiffPixels });
        });
        test('empty', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            const protections = new ProtectionsPage(ntp);
            await ntp.openPage({ additional: { 'protections.feed': 'privacy-stats', activity: 'empty' } });
            await protections.ready();
            await expect(protections.context()).toHaveScreenshot('protections-stats-empty.png', { maxDiffPixels });
        });
        test('dark', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            await ntp.darkMode();
            const protections = new ProtectionsPage(ntp);
            await ntp.openPage({ additional: { 'protections.feed': 'privacy-stats' } });
            await protections.ready();

            await expect(protections.context()).toHaveScreenshot('protections-stats-dark.png', { maxDiffPixels });
        });
    });
    test('activity', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        const protections = new ProtectionsPage(ntp);
        await ntp.openPage({ additional: { 'protections.feed': 'activity' } });
        await protections.ready();

        await expect(protections.context()).toHaveScreenshot('protections-activity.png', { maxDiffPixels });
    });
});
