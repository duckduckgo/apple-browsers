import { test, expect } from '@playwright/test';
import { NewtabPage } from '../../../integration-tests/new-tab.page.js';

test.describe('newtab NextSteps cards', () => {
    test('fetches config + next steps data', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: 'bringStuff' });
        const calls1 = await ntp.mocks.waitForCallCount({ method: 'initialSetup', count: 1 });
        const calls2 = await ntp.mocks.waitForCallCount({ method: 'nextSteps_getData', count: 1 });
        expect(calls1.length).toBe(1);
        expect(calls2.length).toBe(1);
    });

    test('renders a dismiss button', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: 'bringStuff' });
        await page.getByTestId('dismissBtn').click();
        await ntp.mocks.waitForCallCount({ method: 'nextSteps_dismiss', count: 1 });
    });

    test('renders corresponding title text and action text', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: 'bringStuff' });
        await page.getByText('Bring Your Stuff').waitFor();
        await page.getByRole('button', { name: 'Import Now' }).click();
        await ntp.mocks.waitForCallCount({ method: 'nextSteps_action', count: 1 });
        await ntp.openPage({ nextSteps: 'defaultApp' });
        await page.getByText('Set as Default Browser').waitFor();
        await page.getByRole('button', { name: 'Make Default Browser' }).click();
        await ntp.mocks.waitForCallCount({ method: 'nextSteps_action', count: 1 });
    });

    test('renders multiple, shows 2 when collapsed', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: ['bringStuff', 'defaultApp', 'blockCookies', 'duckplayer'] });
        // renders the first two
        await expect(page.getByText('Bring Your Stuff')).toBeVisible();
        await expect(page.getByText('Set as Default Browser')).toBeVisible();
        // does not render the 4th one
        await expect(page.getByRole('button', { name: 'Try DuckPlayer' })).not.toBeVisible();
    });

    test('renders multiple, shows all when expanded', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: ['bringStuff', 'defaultApp', 'blockCookies', 'duckplayer'] });
        // while collapsed, 4th item action button unavailable
        await expect(page.getByRole('button', { name: 'Try DuckPlayer' })).not.toBeVisible();

        await page.locator('[data-entry-point="nextSteps"]').getByRole('button', { name: 'Show More' }).click();

        await expect(page.locator('h3').filter({ hasText: 'Block Cookie Pop-ups' })).toBeVisible();
        await page.getByRole('button', { name: 'Try DuckPlayer' }).click();
        await ntp.mocks.waitForCallCount({ method: 'nextSteps_action', count: 1 });
    });

    test('shows a confirmation state', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ nextSteps: ['addAppToDockMac', 'defaultApp'] });
        await page.getByRole('button', { name: 'Add to Dock' }).click();

        await expect(page.getByText('Added to Dock!')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Add to Dock' })).not.toBeVisible();
    });
});
