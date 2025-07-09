import { test } from '@playwright/test';
import { DuckPlayerPage } from './duck-player.js';

test.describe('duckplayer iframe', () => {
    test('loads the iframe src without a timestamp', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.videoHasFocus();
    });
    test('only accepts first 11 chars of an id', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID('this_has_too_many_chars');
        await duckplayer.hasLoadedIframe('this_has_to');
    });
    test('reflects title from embed', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasTheSameTitleAsEmbed();
    });
    test('loads the iframe src with a timestamp', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithTimestamp('2h3m1s');
        await duckplayer.videoStartsAtTimestamp('7381');
    });
    test('ignores the timestamp when the format is invalid', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithTimestamp('aaaqkw');
        await duckplayer.hasLoadedIframe();
    });
    test('shows error message when video id is invalid', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID('€%dd#"');
        await duckplayer.hasShownErrorMessage();
        await duckplayer.hasNotAddedIframe();
    });
    test('supports "watch on youtube" for unsupported videos', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID('UNSUPPORTED');
        await duckplayer.opensInYoutubeFromError({ videoID: 'UNSUPPORTED' });
    });
    test('clears storage', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.withStorageValues();
        await duckplayer.storageClearedAfterReload();
    });
    test('allows popups from embed', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.allowsPopups();
    });
    test('pip setting', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        duckplayer.pipSettingIs({ state: 'enabled' });
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.hasPipButton();
    });
    test('pip setting disabled', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        duckplayer.pipSettingIs({ state: 'disabled' });
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.pipButtonIsAbsent();
    });
    test('focusMode on by default', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.focusModeIs('on');
    });
    test('focusMode setting', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        duckplayer.focusModeSettingIs({ state: 'enabled' });
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.focusModeIs('on');
    });
    test('focusMode setting disabled', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        duckplayer.focusModeSettingIs({ state: 'disabled' });
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.focusModeIsAbsent();
    });
});

test.describe('duckplayer custom error', () => {
    test('shows custom error screen for videos that require sign-in', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('sign-in-required', 'e90eWYPNtJ8');
        await duckplayer.didShowSignInRequiredError();
    });
    test('supports "watch on youtube" for videos that require sign-in', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('sign-in-required', 'e90eWYPNtJ8');
        await duckplayer.opensDuckPlayerYouTubeLinkFromError({ videoID: 'e90eWYPNtJ8' });
    });
    test('shows custom error screen for videos that are age-restricted', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('age-restricted', 'e90eWYPNtJ8');
        await duckplayer.didShowAgeRestrictedError();
    });
    test('supports "watch on youtube" for videos that are age-restricted', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('age-restricted', 'e90eWYPNtJ8');
        await duckplayer.opensDuckPlayerYouTubeLinkFromError({ videoID: 'e90eWYPNtJ8' });
    });
    test('shows custom error screen for videos that can’t be embedded', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('no-embed', 'e90eWYPNtJ8');
        await duckplayer.didShowNoEmbedError();
    });
    test('supports "watch on youtube" for videos that can’t be embedded', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('no-embed', 'e90eWYPNtJ8');
        await duckplayer.opensDuckPlayerYouTubeLinkFromError({ videoID: 'e90eWYPNtJ8' });
    });
    test('shows custom error screen for videos with unknown errors', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('unknown', 'e90eWYPNtJ8');
        await duckplayer.didShowGenericError();
    });
    test('supports "watch on youtube" for videos with unknown errors', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('unknown', 'e90eWYPNtJ8');
        await duckplayer.opensDuckPlayerYouTubeLinkFromError({ videoID: 'e90eWYPNtJ8' });
    });
    test('shows custom error screen, in Spanish, for videos that require sign-in', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('sign-in-required', 'e90eWYPNtJ8', 'es');
        await duckplayer.didShowSignInRequiredErrorInSpanish();
    });
    test('shows custom error screen, in Spanish, for videos that are age-restricted', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('age-restricted', 'e90eWYPNtJ8', 'es');
        await duckplayer.didShowAgeRestrictedErrorInSpanish();
    });
    test('shows custom error screen, in Spanish, for videos that can’t be embedded', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('no-embed', 'e90eWYPNtJ8', 'es');
        await duckplayer.didShowNoEmbedErrorInSpanish();
    });
    test('shows custom error screen, in Spanish, for videos with unknown errors', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithYouTubeError('unknown', 'e90eWYPNtJ8', 'es');
        await duckplayer.didShowGenericErrorInSpanish();
    });
});

test.describe('duckplayer toolbar', () => {
    test('hides toolbar based on user activity', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();

        // 1. Expect toolbar to be visible at page load
        await duckplayer.toolbarIsVisible();

        // 2. Expect it to be hidden after 2 seconds of inactivity
        await duckplayer.toolbarIsHidden();

        // 3. Expect it to be shown if there is mouse activity
        await page.mouse.move(10, 10);
        await duckplayer.toolbarIsVisible();
    });
    test('clicking on cog icon opens settings', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.opensSettingsInNewTab();
    });
    test('opening in youtube', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.opensInYoutube();
    });
});

test.describe('duckplayer mobile settings', () => {
    test('open setting on tap', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.openSettings();
        await duckplayer.didOpenMobileSettings();
    });
    test('open info modal on tap', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.openInfo();
        await duckplayer.didOpenInfo();
    });
    test('open on Youtube on tap', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.watchOnYoutube();
        await duckplayer.didWatchOnYoutube();
    });
    test('toggles the switch', async ({ page }, workerInfo) => {
        test.skip(isDesktop(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.reducedMotion();
        await page.getByRole('switch').click();
        await page.getByLabel('Keep Duck Player turned on').waitFor({ state: 'hidden' });
        await duckplayer.sentUpdatedSettings();
    });
});

/**
 * Use this test in `--headed` mode to cycle through every language
 */
test.describe('translated DuckPlayer UI', () => {
    test.skip('testing UI for locales', async ({ page }, workerInfo) => {
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
        for (const locale of items) {
            const duckplayer = DuckPlayerPage.create(page, workerInfo);
            await duckplayer.openWithVideoID();
            await duckplayer.hasLoadedIframe();
            const params = new URLSearchParams({
                locale,
                videoID: 'VIDEO_ID',
            });
            await duckplayer.openPage(params);
            await page.pause();
        }
    });
});

test.describe('duckplayer desktop settings', () => {
    test('always open setting', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();

        // wait for settings to have arrived
        await duckplayer.didReceiveFirstSettingsUpdate();
        await duckplayer.settingsAreVisible();

        await page.mouse.move(1, 1);
        await page.mouse.move(10, 10);
        // now toggle and assert we send the message to native
        await duckplayer.toggleAlwaysOpenSetting();
        await duckplayer.sentUpdatedSettings();
    });
    test('always open setting (reduced motion)', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        await duckplayer.reducedMotion();
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();
        await duckplayer.didReceiveFirstSettingsUpdate();
        await duckplayer.settingsAreVisible();
        await page.mouse.move(1, 1);
        await page.mouse.move(10, 10);
        await duckplayer.toggleAlwaysOpenSetting();
        await duckplayer.sentUpdatedSettings();
    });
    test('when a new value arrives via subscription', async ({ page }, workerInfo) => {
        test.skip(isMobile(workerInfo));
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        await duckplayer.openWithVideoID();
        await duckplayer.hasLoadedIframe();

        // wait for settings to have arrived
        await duckplayer.didReceiveFirstSettingsUpdate();
        await duckplayer.settingsAreVisible();

        // now simulate the user enabling the player in settings
        await duckplayer.enabledViaSettings();
        await duckplayer.checkboxWasChecked();
    });
});

test.describe('reporting exceptions', () => {
    test('regular layout', async ({ page }, workerInfo) => {
        const duckplayer = DuckPlayerPage.create(page, workerInfo);
        // load as normal
        await duckplayer.openWithException();
        await duckplayer.showsErrorMessage();
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
