import { test, expect } from '@playwright/test';
import { NewtabPage } from '../../../integration-tests/new-tab.page.js';

test.describe('newtab update notifications', () => {
    test('handles empty notes', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ updateNotification: 'empty' });

        const calls1 = await ntp.mocks.waitForCallCount({ method: 'initialSetup', count: 1 });

        expect(calls1.length).toBe(1);
        const text = page.getByText('Browser Updated to version 1.65.0.');
        await text.waitFor();
        await page.getByRole('button', { name: 'Dismiss' }).click();
        await ntp.mocks.waitForCallCount({ method: 'updateNotification_dismiss', count: 1 });
        await expect(text).not.toBeVisible();
    });
    test('handles populated notes', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ updateNotification: 'populated' });

        const calls1 = await ntp.mocks.waitForCallCount({ method: 'initialSetup', count: 1 });

        expect(calls1.length).toBe(1);

        await page.getByText("Browser Updated to version 1.91. See what's new in this release.").waitFor();
        await page.getByRole('link', { name: "what's new" }).click();
        // this test was updated to add 'exact: true' which would fail if the bullet was not stripped
        await page.getByText('Bug fixes and improvements', { exact: true }).waitFor();
        await page.getByText('Optimized performance for faster load times', { exact: true }).waitFor();
        await page.getByRole('button', { name: 'Dismiss' }).click();
        await ntp.mocks.waitForCallCount({ method: 'updateNotification_dismiss', count: 1 });
    });
    test('handles multiple lists', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage({ updateNotification: 'multipleSections' });
        await page.getByRole('link', { name: "what's new" }).click();
        await expect(page.locator('[data-entry-point="updateNotification"]')).toMatchAriaSnapshot(`
        - group:
          - list:
            - listitem: We're excited to introduce a new browsing feature - Fire Windows. These special windows work the same way as normal windows, except they isolate your activity from other browsing data and self-destruct when closed. This means you can use a Fire Window to browse without saving local history or to sign into a site with a different account. You can open a new Fire Window anytime from the Fire Button menu.
            - listitem: Try the new bookmark management view that opens in a tab for more robust bookmark organization.
          - paragraph: For Privacy Pro subscribers
          - list:
            - listitem: VPN notifications are now available to help communicate VPN status.
            - listitem: Some apps aren't compatible with VPNs. You can now exclude these apps to use them while connected to the VPN.
            - listitem: Visit https://duckduckgo.com/pro for more information.
        `);
    });
});
