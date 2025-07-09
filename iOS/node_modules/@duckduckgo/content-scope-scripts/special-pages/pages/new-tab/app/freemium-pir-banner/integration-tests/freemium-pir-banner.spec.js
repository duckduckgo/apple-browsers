import { test, expect } from '@playwright/test';
import { NewtabPage } from '../../../integration-tests/new-tab.page.js';

test.describe('newtab remote messaging framework freemiumPIRBanner', () => {
    test('fetches config + data', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ pir: 'onboarding' });

        const calls1 = await ntp.mocks.waitForCallCount({ method: 'initialSetup', count: 1 });
        const calls2 = await ntp.mocks.waitForCallCount({ method: 'freemiumPIRBanner_getData', count: 1 });

        expect(calls1.length).toBe(1);
        expect(calls2.length).toBe(1);
    });

    test('onboarding variant renders a title, descriptionText with strong tag, an action button, and dismiss button', async ({
        page,
    }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ pir: 'onboarding' });
        await page.getByRole('heading', { name: 'Personal Information Removal' }).waitFor();
        await page.getByText('Find out which sites are').waitFor();
        await page.locator('strong').waitFor();

        await page.getByRole('button', { name: 'Free Scan' }).click();
        await ntp.mocks.waitForCallCount({ method: 'freemiumPIRBanner_action', count: 1 });
        await page.getByTestId('dismissBtn').click();
        await ntp.mocks.waitForCallCount({ method: 'freemiumPIRBanner_dismiss', count: 1 });
    });

    test('scan_results variant renders descriptionText, an action button, and dismiss button', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ pir: 'scan_results' });

        await page.getByText('Your free personal').waitFor();
        await page.getByRole('button', { name: 'View Results' }).click();
        await page.getByTestId('dismissBtn').click();
        await ntp.mocks.waitForCallCount({ method: 'freemiumPIRBanner_action', count: 1 });
        await ntp.mocks.waitForCallCount({ method: 'freemiumPIRBanner_dismiss', count: 1 });
    });
});
