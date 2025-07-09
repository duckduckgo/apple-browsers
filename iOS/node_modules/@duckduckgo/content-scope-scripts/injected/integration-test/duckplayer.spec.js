import { test } from '@playwright/test';
import { DuckplayerOverlays } from './page-objects/duckplayer-overlays.js';

test.describe('Thumbnail Overlays', () => {
    test('Overlays show on thumbnails when enabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.gotoThumbsPage();

        // When I hover any video thumbnail
        await overlays.hoverAThumbnail();

        // Then our overlay shows
        await overlays.isVisible();
    });
    test('Overlays never appear on "shorts"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig();
        await overlays.gotoThumbsPage();

        // Ensure the hover works normally to prevent false positives
        await overlays.hoverAThumbnail();
        await overlays.isVisible();

        // now ensure the hover doesn't work on shorts
        await overlays.hoverShort();
        await overlays.overlaysDontShow();
    });
    /**
     * https://app.asana.com/0/1201048563534612/1204993915251837/f
     */
    test('Clicks are not intercepted on shorts when "enabled"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.withRemoteConfig();
        await overlays.userSettingIs('enabled');
        await overlays.gotoThumbsPage();
        const navigation = overlays.requestWillFail();
        await overlays.clicksFirstShortsThumbnail();
        const url = await navigation;
        overlays.opensShort(url);
    });
    test("Overlays don't show on thumbnails when disabled", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is disabled
        await overlays.overlaysDisabled();
        await overlays.gotoThumbsPage();

        // Then our overlays never show
        await overlays.overlaysDontShow();
    });
    test('Overlays link to Duck Player', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.gotoThumbsPage();

        // When I click the DDG overlay
        await overlays.clickDDGOverlay();

        // Then our player loads for the correct video
        await overlays.duckPlayerLoadsFor('1');
    });
    test('Overlays dont show when user setting is "enabled"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.userSettingIs('enabled');
        await overlays.gotoThumbsPage();
        await overlays.overlaysDontShow();
    });
    test('Overlays dont show when user setting is "disabled"', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.userSettingIs('disabled');
        await overlays.gotoThumbsPage();
        await overlays.overlaysDontShow();
    });
    test('Overlays appear when updated settings arrive', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.userSettingIs('disabled');
        await overlays.gotoThumbsPage();

        // Nothing shown initially
        await overlays.overlaysDontShow();

        // now receive an update
        await overlays.userChangedSettingTo('always ask');

        // overlays act as normal
        await overlays.hoverAThumbnail();
        await overlays.isVisible();
    });
    test('Overlays disappear when updated settings arrive', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given the "overlays" feature is enabled
        await overlays.withRemoteConfig();
        await overlays.userSettingIs('always ask');
        await overlays.gotoThumbsPage();

        // overlays act as normal initially
        await overlays.hoverAThumbnail();
        await overlays.isVisible();

        // now receive an update
        await overlays.userChangedSettingTo('disabled');

        // overlays should be removed
        await overlays.overlaysDontShow();
    });
});

test.describe('Video Player overlays', () => {
    test('Overlay blocks video from playing', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        // Then the overlay shows and blocks the video from playing
        await overlays.overlayBlocksVideo();
    });
    test('Overlay blocks video from playing (supporting DOM appearing over time)', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage({ variant: 'incremental-dom' });

        // Then the overlay shows and blocks the video from playing
        await overlays.overlayBlocksVideo();
    });
    test('Overlay is removed when new settings arrive', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        // then the overlay shows and blocks the video from playing
        await overlays.overlayBlocksVideo();

        // When the user changes settings though
        await overlays.userChangedSettingTo('disabled');

        // No small overlays
        await overlays.overlaysDontShow();
        // No video overlay
        await overlays.videoOverlayDoesntShow();
    });
    test('Overlay alters to suit new video id after navigation', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig({ json: 'overlays.json' });

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage({ videoID: '123456' });

        // then the overlay shows and blocks the video from playing
        await overlays.overlayBlocksVideo();
        await overlays.hasWatchLinkFor({ videoID: '123456' });

        // now simulate going to another video from the related feed
        await overlays.clickRelatedThumb({ videoID: 'abc1' });

        // should still be visible
        await overlays.overlayBlocksVideo();

        // and watch link is updated
        await overlays.hasWatchLinkFor({ videoID: 'abc1' });
    });
    test('Small overlay is displayed on video', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask remembered');
        await overlays.gotoPlayerPage();

        // Then the overlay shows and blocks the video from playing
        await overlays.smallOverlayShows();
    });
    test("Small overlay is shown when setting is 'enabled'", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('enabled');
        await overlays.gotoPlayerPage();

        // Then the overlay shows and blocks the video from playing
        await overlays.smallOverlayShows();
    });
    test("Overlays are not shown when setting is 'disabled'", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('disabled');
        await overlays.gotoPlayerPage();

        // No small overlays
        await overlays.overlaysDontShow();
        // No video overlay
        await overlays.videoOverlayDoesntShow();
    });
    test("Selecting 'Turn On Duck Player'", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.turnOnDuckPlayer();
        await overlays.userSettingWasUpdatedTo('always ask'); // not updated
    });
    test("Selecting 'Turn On Duck Player' + remember", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.rememberMyChoice();
        await overlays.turnOnDuckPlayer();
        await overlays.userSettingWasUpdatedTo('enabled'); // updated
    });
    test("Selecting 'No Thanks'", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.noThanks();
        await overlays.secondOverlayExistsOnVideo();
    });
    test("Selecting 'No Thanks' + remember", async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);

        // Given overlays feature is enabled
        await overlays.withRemoteConfig();

        // And my setting is 'always ask'
        await overlays.userSettingIs('always ask');
        await overlays.gotoPlayerPage();

        await overlays.rememberMyChoice();
        await overlays.noThanks();
        await overlays.userSettingWasUpdatedTo('always ask remembered'); // updated
    });
    test.describe('with remote config overrides', () => {
        test("Selecting 'No Thanks' + remember", async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);

            // config with some CSS selectors overridden
            await overlays.withRemoteConfig({ json: 'video-alt-selectors.json' });

            // And my setting is 'always ask'
            await overlays.userSettingIs('always ask');
            await overlays.gotoPlayerPage({ pageType: 'videoAltSelectors' });
            await overlays.overlayBlocksVideo();
        });
    });
    test.describe('with UI settings overrides', () => {
        test('displays default overlay copy', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);

            // Given overlays feature is enabled
            await overlays.withRemoteConfig();

            // And my setting is 'always ask'
            // And no overlay copy experiment cohort is set
            await overlays.initialSetupIs('always ask');
            await overlays.gotoPlayerPage();

            // Then the overlay shows the correct copy for the default variant
            await overlays.overlayCopyIsDefault();
        });

        test('forces next video to play in Duck Player', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);

            // Given overlays feature is enabled
            await overlays.withRemoteConfig();

            // And my setting is 'always ask'
            // And the UI setting for 'play in Duck Player' is set to true
            await overlays.initialSetupIs('always ask', 'play in duck player');
            await overlays.gotoThumbsPage();
            await overlays.overlaysDontShow();

            // When I click on the first thumbnail
            await overlays.clicksFirstThumbnail();

            // Then our player loads for the correct video
            await overlays.duckPlayerLoadsFor('1');
        });

        test('forces next video to play in Duck Player after UI settings change', async ({ page }, workerInfo) => {
            const overlays = DuckplayerOverlays.create(page, workerInfo);

            // Given overlays feature is enabled
            await overlays.withRemoteConfig();

            // And my setting is 'always ask'
            // And the UI setting for 'play in Duck Player' is not set
            await overlays.initialSetupIs('always ask');
            await overlays.gotoThumbsPage();

            // Then overlays act as normal initially
            await overlays.hoverAThumbnail();
            await overlays.isVisible();

            // When a UI settings update arrives
            await overlays.uiChangedSettingTo('play in duck player');

            // And I click on the first thumbnail
            await overlays.clicksFirstThumbnail();

            // Then our player loads for the correct video
            await overlays.duckPlayerLoadsFor('1');
        });
    });
});

test.describe('serp proxy', () => {
    test('serp proxy is enabled', async ({ page }, workerInfo) => {
        const overlays = DuckplayerOverlays.create(page, workerInfo);
        await overlays.serpProxyEnabled();
        await overlays.gotoSerpProxyPage();
        await overlays.userValuesCallIsProxied();
    });
});
