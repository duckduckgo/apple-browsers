import { expect, test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';

test.describe('Video Player overlays', () => {
    test("Selecting 'watch here' on mobile", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        // watch here = overlays removed
        await overlays.mobile.choosesWatchHere();
        await overlays.mobile.overlayIsRemoved();
        await overlays.pixels.sendsPixels([
            { pixelName: 'overlay', params: {} },
            { pixelName: 'play.do_not_use', params: { remember: '0' } },
        ]);
    });
    test("Selecting 'watch here' on mobile + remember", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        // watch here = overlays removed
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

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.mobile.choosesDuckPlayer();
        await overlays.pixels.sendsPixels([
            { pixelName: 'overlay', params: {} },
            { pixelName: 'play.use', params: { remember: '0' } },
        ]);
        await overlays.userSettingWasUpdatedTo('always ask');
    });
    test("Selecting 'watch in duckplayer' on mobile + remember", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.mobile.selectsRemember();
        await overlays.mobile.choosesDuckPlayer();
        await overlays.pixels.sendsPixels([
            { pixelName: 'overlay', params: {} },
            { pixelName: 'play.use', params: { remember: '1' } },
        ]);
        await overlays.userSettingWasUpdatedTo('enabled');
    });
    test('opens info', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

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
            await overlays.withRemoteConfig({ locale });
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage();
            await page.locator('ddg-video-overlay-mobile').nth(0).waitFor();
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
        await overlays.withRemoteConfig({ locale: 'en' });
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();
        await page.locator('ddg-video-overlay-mobile').nth(0).waitFor();
        await expect(page.locator('.html5-video-player')).toHaveScreenshot('overlay.png', { maxDiffPixels: 20 });
    });
});
