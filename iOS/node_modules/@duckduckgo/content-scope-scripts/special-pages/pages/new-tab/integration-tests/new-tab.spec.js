import { expect, test } from '@playwright/test';
import { NewtabPage } from './new-tab.page.js';
import { CustomizerPage } from '../app/customizer/integration-tests/customizer.page.js';

test.describe('newtab widgets', () => {
    test('widget config single click', async ({ page }, workerInfo) => {
        await page.clock.install();

        const ntp = NewtabPage.create(page, workerInfo);
        const cp = new CustomizerPage(ntp);
        await ntp.reducedMotion();
        await ntp.openPage();
        await cp.opensCustomizer();

        // hide
        await page.getByRole('switch', { name: 'Toggle Protections Report' }).uncheck();

        // debounced
        await page.clock.fastForward(501);

        // verify the single sync call, where one is hidden
        const outgoing = await ntp.mocks.outgoing({ names: ['widgets_setConfig'] });

        expect(outgoing).toStrictEqual([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'newTabPage',
                    params: [
                        { id: 'favorites', visibility: 'visible' },
                        { id: 'protections', visibility: 'hidden' },
                    ],
                    method: 'widgets_setConfig',
                },
            },
        ]);
    });
    test.skip('widget config double click', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage();

        // menu
        await page.getByRole('button', { name: 'Customize' }).click();

        // hide
        await page.locator('label').filter({ hasText: 'Blocked Tracking Attempts' }).uncheck();

        // show
        await page.locator('label').filter({ hasText: 'Blocked Tracking Attempts' }).check();

        // debounced
        await page.waitForTimeout(500);

        // verify the single sync call, where both are visible.
        const outgoing = await ntp.mocks.outgoing({ names: ['widgets_setConfig'] });
        expect(outgoing).toStrictEqual([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'newTabPage',
                    params: [
                        { id: 'favorites', visibility: 'visible' },
                        { id: 'protections', visibility: 'visible' },
                    ],
                    method: 'widgets_setConfig',
                },
            },
        ]);
    });
    test('context menu', async ({ page }, workerInfo) => {
        const ntp = NewtabPage.create(page, workerInfo);
        await ntp.reducedMotion();
        await ntp.openPage();

        // wait for the menu, as a signal that the JS is ready
        await page.getByRole('button', { name: 'Customize' }).waitFor();

        await page.locator('body').click({ button: 'right' });

        const calls = await ntp.mocks.waitForCallCount({ method: 'contextMenu', count: 1 });
        expect(calls[0].payload).toStrictEqual({
            context: 'specialPages',
            featureName: 'newTabPage',
            method: 'contextMenu',
            params: {
                visibilityMenuItems: [
                    {
                        id: 'favorites',
                        title: 'Favorites',
                    },
                    {
                        id: 'protections',
                        title: 'Protections Report',
                    },
                ],
            },
        });
    });
    test.describe('default background colors', () => {
        test('default background light', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            await ntp.openPage();
            await ntp.waitForCustomizer();
            await ntp.hasBackgroundColor({ hex: '#fafafa' });
        });
        test('default background dark', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            await ntp.darkMode();
            await ntp.openPage();
            await ntp.waitForCustomizer();
            await ntp.hasBackgroundColor({ hex: '#333333' });
        });
        test('with overrides from initial setup (light)', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            await ntp.openPage({ additional: { defaultStyles: 'visual-refresh' } });
            await ntp.waitForCustomizer();
            await page.pause();
            await ntp.hasBackgroundColor({ hex: '#E9EBEC' });
        });
        test('with overrides from initial setup (dark)', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            await ntp.reducedMotion();
            await ntp.darkMode();
            await ntp.openPage({ additional: { defaultStyles: 'visual-refresh' } });
            await ntp.waitForCustomizer();
            await ntp.hasBackgroundColor({ hex: '#27282A' });
        });
        test('with pushed updated theme value (light)', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const cp = new CustomizerPage(ntp);
            await ntp.reducedMotion();
            await ntp.openPage({});
            await ntp.waitForCustomizer();
            await cp.acceptsThemeUpdateWithDefaults('light', { darkBackgroundColor: '#000000', lightBackgroundColor: '#ffffff' });
            await ntp.hasBackgroundColor({ hex: '#ffffff' });
        });
        test('with pushed updated theme value (dark)', async ({ page }, workerInfo) => {
            const ntp = NewtabPage.create(page, workerInfo);
            const cp = new CustomizerPage(ntp);
            await ntp.reducedMotion();
            await ntp.darkMode();
            await ntp.openPage({});
            await ntp.waitForCustomizer();
            await cp.acceptsThemeUpdateWithDefaults('dark', { darkBackgroundColor: '#000000', lightBackgroundColor: '#ffffff' });
            await ntp.hasBackgroundColor({ hex: '#000000' });
        });
    });
});
