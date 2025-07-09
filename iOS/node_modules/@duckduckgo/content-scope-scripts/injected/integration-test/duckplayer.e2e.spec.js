import { test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';

test.describe('e2e: Duck Player Thumbnail Overlays on YouTube.com', () => {
    test('e2e: Overlays never appear on "shorts"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        await overlays.withRemoteConfig({ json: 'overlays-live.json' });
        await overlays.gotoYoutubeHomepage();

        // Ensure the hover works normally to prevent false positives
        await overlays.hoverAYouTubeThumbnail();
        await overlays.isVisible();

        // now ensure the hover doesn't work on shorts
        await overlays.hoverShort();
        await overlays.overlaysDontShow();
    });
    test('e2e: Overlays appear on "search pages"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        await overlays.withRemoteConfig({ json: 'overlays-live.json' });
        await overlays.gotoYoutubeSearchPageForMovie();
        await overlays.hoverAYouTubeThumbnail();
        await overlays.isVisible();

        await overlays.hoverAMovieThumb();
        await overlays.overlaysDontShow();
    });
    test('control (without our script): clicking on a short loads correctly', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.gotoYoutubeHomepage();
        await page.waitForTimeout(2000);
        await overlays.clicksFirstShortsThumbnail();
        await overlays.showsShortsPage();
    });
    test.describe('when enabled', () => {
        test('shorts do not intercept clicks', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-live.json' });
            await overlays.userSettingIs('enabled');
            await overlays.gotoYoutubeHomepage();
            await page.waitForTimeout(2000);
            await overlays.clicksFirstShortsThumbnail();
            await overlays.showsShortsPage();
        });
        test('settings can change to disabled', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-live.json' });
            await overlays.userSettingIs('enabled');
            await overlays.gotoYoutubeHomepage();

            await test.step('initial load, clicking a thumb -> duck player', async () => {
                const videoId = await overlays.clicksFirstThumbnail();
                await overlays.duckPlayerLoadsFor(videoId);
            });

            await test.step('settings updated to `disabled` -> YT', async () => {
                await overlays.userChangedSettingTo('disabled');
                const videoId = await overlays.clicksFirstThumbnail();
                await overlays.showsVideoPageFor(videoId);
            });
        });
    });
    test.describe('when disabled', () => {
        test('disabled', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-live.json' });
            await overlays.userSettingIs('disabled');
            await overlays.gotoYoutubeHomepage();

            await test.step('clicking first thumb -> video', async () => {
                const videoId = await overlays.clicksFirstThumbnail();
                await overlays.showsVideoPageFor(videoId);
            });

            await test.step('click first thumb with setting enabled', async () => {
                await overlays.gotoYoutubeHomepage();
                await overlays.userChangedSettingTo('enabled');
                const videoId = await overlays.clicksFirstThumbnail();
                await overlays.duckPlayerLoadsFor(videoId);
            });
        });
    });
    test.describe('e2e: video overlay', () => {
        test('setting: always ask', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-live.json' });
            await overlays.userSettingIs('always ask');
            await overlays.gotoYoutubeVideo();
            await overlays.overlayBlocksVideo();
        });
        test('setting: disabled', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);
            await overlays.withRemoteConfig({ json: 'overlays-live.json' });
            await overlays.userSettingIs('always ask');
            await overlays.gotoYoutubeVideo();
            await overlays.overlayBlocksVideo();
            await overlays.userChangedSettingTo('enabled');
        });
    });
});
