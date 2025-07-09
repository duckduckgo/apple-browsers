import { expect, test } from '@playwright/test';
import { DuckPlayerPage } from './duck-player.js';

test.describe('screenshots @screenshots', () => {
    test('regular layout', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await expect(page).toHaveScreenshot('regular-layout.png', { maxDiffPixels: 20 });
    });
    test('layout when enabled', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        duckplayer.playerIsEnabled();
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.didReceiveFirstSettingsUpdate();
        await expect(page).toHaveScreenshot('enabled-layout.png', { maxDiffPixels: 20 });
    });
    test('player error', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID('€%dd#"');
        await duckplayer.hasShownErrorMessage();
        await expect(page).toHaveScreenshot('error-layout.png', { maxDiffPixels: 20 });
    });
    test('youtube sign-in error', async ({ page }, workerInfo) => {
        test.skip(!isApple(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('sign-in-required');
        await duckplayer.didShowSignInRequiredError();
        await expect(page).toHaveScreenshot('youtube-error-sign-in-required.png', { maxDiffPixels: 20 });
    });
    test('youtube age-restricted error', async ({ page }, workerInfo) => {
        test.skip(!isApple(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('age-restricted');
        await duckplayer.didShowAgeRestrictedError();
        await expect(page).toHaveScreenshot('youtube-error-age-restricted.png', { maxDiffPixels: 20 });
    });
    test('youtube no-embed error', async ({ page }, workerInfo) => {
        test.skip(!isApple(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('no-embed');
        await duckplayer.didShowNoEmbedError();
        await expect(page).toHaveScreenshot('youtube-error-no-embed.png', { maxDiffPixels: 20 });
    });
    test('youtube generic error', async ({ page }, workerInfo) => {
        test.skip(!isApple(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('unknown');
        await duckplayer.didShowGenericError();
        await expect(page).toHaveScreenshot('youtube-error-unknown.png', { maxDiffPixels: 20 });
    });
    test('tooltip shown on hover', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithoutFocusMode();
        await duckplayer.hasLoadedIframe();

        await duckplayer.infoTooltipIsShowsOnFocus();
        await expect(page).toHaveScreenshot('tooltip.png', { maxDiffPixels: 20 });
        await duckplayer.infoTooltipHides();
    });
});

/**
 * @param {import("@playwright/test").TestInfo} testInfo
 */
function isMobile(testInfo) {
    const u = /** @type {any} */ (testInfo.project.use);
    return u?.platform === 'android' || u?.platform === 'ios';
}

/**
 * @param {import("@playwright/test").TestInfo} testInfo
 */
function isApple(testInfo) {
    const u = /** @type {any} */ (testInfo.project.use);
    return u?.platform === 'macos' || u?.platform === 'ios';
}
