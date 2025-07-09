import { test } from '@playwright/test';
import { DuckPlayerPage } from './duck-player.js';

test.describe('duckplayer telemetry', () => {
    test('sends a landscape impression', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.didSendTelemetry({ attributes: { name: 'impression', value: 'landscape-layout' } });
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
function isDesktop(testInfo) {
    return !isMobile(testInfo);
}
