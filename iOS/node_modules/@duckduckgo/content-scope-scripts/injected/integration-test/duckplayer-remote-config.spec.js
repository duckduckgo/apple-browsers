import { test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';

test.describe('Remote config', () => {
    test('feature: disabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'disabled.json' });
        await overlays.gotoThumbsPage();
        await overlays.overlaysDontShow();
    });
    test('thumbnailOverlays: disabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'thumbnail-overlays-disabled.json' });
        await overlays.gotoThumbsPage();
        await overlays.overlaysDontShow();
    });
    test('clickInterception: disabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'click-interceptions-disabled.json' });
        await overlays.userSettingIs('enabled');
        await overlays.gotoThumbsPage();
        const navigation = overlays.requestWillFail();
        await overlays.clicksFirstThumbnail();
        await navigation;
    });
    test('videoOverlays: disabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'video-overlays-disabled.json' });
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();
        await page.waitForTimeout(1000); // <-- We need to prove the overlay doesn't show.
        await overlays.videoOverlayDoesntShow();
    });
    test('excludedRegions: CSS selectors on video page', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'overlays.json' });
        await overlays.gotoPlayerPage();
        await overlays.overlayBlocksVideo();
        await overlays.hoverAThumbnailInExcludedRegion('#playlist');
        await overlays.overlaysDontShow();
    });
    test('hoverExcluded: CSS selectors to ignore hovers', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'overlays.json' });
        await overlays.gotoThumbsPage({ variant: 'cookie_banner' });

        // this is covered with a known overlay
        await overlays.hoverNthThumbnail(0);

        // assert Dax doesn't show
        await overlays.overlaysDontShow();

        // now hover a thumb without the overlay
        await overlays.hoverNthThumbnail(3);

        // overlay should be visible
        await overlays.isVisible();
    });
    test('clickExcluded: CSS selectors to ignore clicks', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig({ json: 'overlays.json' });
        await overlays.userSettingIs('enabled');

        await overlays.gotoThumbsPage({ variant: 'cookie_banner' });

        // control - ensure messages are being sent, to prevent false positives
        // this thumb does NOT have the overlay
        await overlays.clickNthThumbnail(3);
        await overlays.duckPlayerLoadsFor('4'); // this is ID of the 4th element

        // now click the first thumb, that's covered with an overlay
        await overlays.clickNthThumbnail(0);
        await overlays.duckPlayerLoadedTimes(1); // still 1, from the first call
    });
});
