import { test } from '@playwright/test';
import { DuckPlayerNative } from './page-objects/duckplayer-native.js';

test.describe('Duck Player Native messaging', () => {
    test('Calls initial setup', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();

        // Then Initial Setup should be called
        await duckPlayer.didSendInitialHandshake();

        // And an onDuckPlayerScriptsReady event should be called
        await duckPlayer.didSendDuckPlayerScriptsReady();
    });

    test('Responds to onUrlChanged', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();

        // And the frontend receives an onUrlChanged event
        await duckPlayer.sendURLChanged('NOCOOKIE');

        // Then an onDuckPlayerScriptsReady event should be fired twice
        await duckPlayer.didSendDuckPlayerScriptsReady(2);
    });

    test('Polls timestamp on YouTube', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();

        // Then the current timestamp should be polled back to the browser
        await duckPlayer.didSendCurrentTimestamp();
    });

    test('Polls timestamp on NoCookie page', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a NoCookie page
        await duckPlayer.gotoNoCookiePage();

        // Then the current timestamp should be polled back to the browser
        await duckPlayer.didSendCurrentTimestamp();
    });
});

test.describe('Duck Player Native thumbnail overlay', () => {
    test('Shows overlay on YouTube player page', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();
        await duckPlayer.sendOnMediaControl();

        // Then I should see the thumbnail overlay in the page
        await duckPlayer.didShowOverlay();
        await duckPlayer.didShowLogoInOverlay();
    });
    test('Does not duplicate overlay on repeated calls', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();
        await duckPlayer.sendOnMediaControl();

        // And the browser fires multiple pause messages
        await duckPlayer.sendOnMediaControl();
        await duckPlayer.sendOnMediaControl();

        // Then I should see only one thumbnail overlay on the page
        await duckPlayer.overlayIsUnique();
    });
    test('Dismisses overlay on click', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page
        await duckPlayer.gotoYouTubePage();
        await duckPlayer.sendOnMediaControl();

        // And I see the thumbnail overlay in the page
        await duckPlayer.didShowOverlay();

        // And I click on the overlay
        await duckPlayer.clickOnOverlay();

        // Then the overlay should be dismissed
        await duckPlayer.didDismissOverlay();

        // And a didDismissOverlay event should be fired
        await duckPlayer.didSendOverlayDismissalMessage();
    });
});

test.describe('Duck Player Native custom error view', () => {
    test('Shows sign-in error', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page with an age-restricted error
        await duckPlayer.gotoSignInErrorPage();

        // Then I should see the generic error screen
        await duckPlayer.didShowSignInError();
    });

    test('Shows age-restricted error', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page with an age-restricted error
        await duckPlayer.gotoAgeRestrictedErrorPage();

        // Then I should see the generic error screen
        await duckPlayer.didShowAgeRestrictedError();
    });

    test('Shows no-embed error', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page with an age-restricted error
        await duckPlayer.gotoNoEmbedErrorPage();

        // Then I should see the generic error screen
        await duckPlayer.didShowNoEmbedError();
    });

    test('Shows generic/unknown error', async ({ page }, workerInfo) => {
        const duckPlayer = DuckPlayerNative.create(page, workerInfo);

        // Given the duckPlayerNative feature is enabled
        await duckPlayer.withRemoteConfig();

        // When I go to a YouTube page with an age-restricted error
        await duckPlayer.gotoUnknownErrorPage();

        // Then I should see the generic error screen
        await duckPlayer.didShowUnknownError();
    });
});
