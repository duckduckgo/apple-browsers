import { expect, test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';

test.describe('Duck Player - Drawer UI variant', () => {
    test.describe('Video Player overlays', () => {
        test("Selecting 'watch here' on mobile", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            // watch here = overlays removed
            await overlays.mobile.drawerIsPresented();
            await overlays.mobile.choosesWatchHere();
            await overlays.mobile.overlayIsRemoved();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.do_not_use', params: { remember: '0' } },
            ]);
        });
        test("Selecting 'watch here' on mobile + remember", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            // watch here = overlays removed
            await overlays.mobile.drawerIsPresented();
            await overlays.mobile.selectsRemember();
            await overlays.mobile.choosesWatchHere();
            await overlays.mobile.overlayIsRemoved();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.do_not_use', params: { remember: '1' } },
            ]);
            await overlays.userSettingWasUpdatedTo('disabled');
        });
        test("Selecting 'watch in duckplayer' on mobile", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            await overlays.mobile.drawerIsPresented();
            await overlays.mobile.choosesDuckPlayer();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.use', params: { remember: '0' } },
            ]);
            await overlays.userSettingWasUpdatedTo('always ask');
        });
        test("Selecting 'watch in duckplayer' on mobile + remember", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            await overlays.mobile.drawerIsPresented();
            await overlays.mobile.selectsRemember();
            await overlays.mobile.choosesDuckPlayer();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.use', params: { remember: '1' } },
            ]);
            await overlays.userSettingWasUpdatedTo('enabled');
        });
        test('Clicking on video thumbnail dismisses overlay', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            await overlays.mobile.clicksOnVideoThumbnail();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.do_not_use.dismiss', params: {} },
            ]);
            await overlays.userSettingWasNotUpdated();
        });
        test('Clicking on drawer backdrop dismisses overlay', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();

            await overlays.mobile.clicksOnDrawerBackdrop();
            await overlays.pixels.sendsPixels([
                { pixelName: 'overlay', params: {} },
                { pixelName: 'play.do_not_use.dismiss', params: {} },
            ]);
            await overlays.userSettingWasNotUpdated();
        });
        test('opens info', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.reducedMotion();

            // Given drawer overlay variant is set
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();
            await overlays.mobile.opensInfo();
        });
    });

    /**
     * Use this test in `--headed` mode to cycle through every language
     */
    test.describe.skip('Translated Overlays', () => {
        const items = [
            'bg',
            'cs',
            'da',
            'de',
            'el',
            'en',
            'es',
            'et',
            'fi',
            'fr',
            'hr',
            'hu',
            'it',
            'lt',
            'lv',
            'nb',
            'nl',
            'pl',
            'pt',
            'ro',
            'ru',
            'sk',
            'sl',
            'sv',
            'tr',
        ];
        // const items = ['en']
        for (const locale of items) {
            test(`testing UI ${locale}`, async ({ page }, workerInfo) => {
                // console.log(workerInfo.project.use.viewport.height)
                // console.log(workerInfo.project.use.viewport.width)
                const overlays = DuckplayerOverlays.create(page, workerInfo);
                await overlays.withRemoteConfig({ json: 'overlays-drawer.json', locale });
                await overlays.userSettingIs('always ask');
                await overlays.gotoPlayerPage();
                await page.locator('ddg-video-drawer-mobile').nth(0).waitFor();
                await page.locator('.html5-video-player').screenshot({ path: `screens/se-2/${locale}.png` });
            });
        }
    });

    /**
     * Use `npm run playwright-screenshots` to run this test only.
     */
    test.describe('Overlay screenshot @screenshots', () => {
        test("testing Overlay UI 'en'", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-drawer.json', locale: 'en' });
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();
            await page.locator('ddg-video-drawer-mobile').nth(0).waitFor();
            await expect(page.locator('ddg-video-drawer-mobile')).toHaveScreenshot('drawer.png', { maxDiffPixels: 20 });
        });
    });
});
