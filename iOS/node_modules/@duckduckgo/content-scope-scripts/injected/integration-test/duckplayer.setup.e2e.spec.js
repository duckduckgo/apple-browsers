import { test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';
import { STORAGE_STATE } from '../playwright-e2e.config.js';

test.describe('e2e: Dismiss cookies', () => {
    test('storage locally', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        await overlays.withRemoteConfig({ json: 'overlays-live.json' });
        await overlays.gotoYoutubeHomepage();
        await overlays.dismissCookies();

        await page.context().storageState({ path: STORAGE_STATE });
    });
});
