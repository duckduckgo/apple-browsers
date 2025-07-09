import { Mocks } from '../../../shared/mocks.js';
import { expect } from '@playwright/test';
import { join } from 'node:path';
import { perPlatform } from 'injected/integration-test/type-helpers.mjs';

const MOCK_VIDEO_ID = 'VIDEO_ID';
const MOCK_VIDEO_TITLE = 'Embedded Video - YouTube';
const youtubeEmbed = (id) =>
    'https://www.youtube-nocookie.com/embed/' + id + '?iv_load_policy=1&autoplay=1&rel=0&modestbranding=1&color=white';
const youtubeEmbedIOS = (id) =>
    'https://www.youtube-nocookie.com/embed/' + id + '?iv_load_policy=1&autoplay=1&muted=1&rel=0&modestbranding=1&color=white';
const html = {
    unsupported: `<html><head><title>${MOCK_VIDEO_TITLE}</title></head>
<body>
<div class="ytp-error" role="alert" data-layer="4">
    <div class="ytp-error-content" style="padding-top: 175.5px;">
        <div class="ytp-error-content-wrap">
            <div class="ytp-error-content-wrap-reason"><span>Video unavailable</span></div>
            <div class="ytp-error-content-wrap-subreason"><span>This video contains content from Example.com, who has blocked it from display on this website or application<br><a
                    href="http://www.youtube.com/watch?v=UNSUPPORTED&amp;feature=emb_err_woyt" target="_blank">Watch on YouTube</a></span>
            </div>
        </div>
    </div>
</div>
</body>
</html>`,
    signInRequired: `<html><head><title>${MOCK_VIDEO_TITLE}</title></head>
<body>
<div class="ytp-error" role="alert" data-layer="4">
  <div class="ytp-error-content" style="padding-top: 165px">
    <div class="ytp-error-content-wrap">
      <div class="ytp-error-content-wrap-reason"><span>Sign in to confirm you’re not a bot</span></div>
      <div class="ytp-error-content-wrap-subreason">
        <span
          ><span>This helps protect our community. </span
          ><a
            href="https://support.google.com/youtube/answer/3037019#zippy=%2Ccheck-that-youre-signed-into-youtube"
            >Learn more</a
          ></span
        >
      </div>
    </div>
  </div>
</div>
</body>
</html>`,
};

/**
 * @typedef {import('injected/integration-test/type-helpers.mjs').Build} Build
 * @typedef {import('injected/integration-test/type-helpers.mjs').PlatformInfo} PlatformInfo
 */

export class DuckPlayerPage {
    /**
     * @param {import("@playwright/test").Page} page
     * @param {Build} build
     * @param {PlatformInfo} platform
     */
    constructor(page, build, platform) {
        this.page = page;
        this.build = build;
        this.platform = platform;
        this.mocks = new Mocks(page, build, platform, {
            context: 'specialPages',
            featureName: 'duckPlayerPage',
            env: 'development',
        });
        // default mocks - just enough to render the first page without error
        this.defaults = {
            // /** @type {Awaited<ReturnType<import("../../pages/duckplayer/src/js/index.js").DuckPlayerPageMessages['initialSetup']>>} */
            initialSetup: {
                settings: {
                    pip: {
                        state: 'disabled',
                    },
                },
                userValues: {
                    privatePlayerMode: { alwaysAsk: {} },
                    overlayInteracted: false,
                },
                locale: 'en',
                env: 'development',
                platform: this.platform.name === 'windows' ? undefined : { name: this.platform.name },
            },
            /** @type {import('../types/duckplayer.ts').UserValues} */
            getUserValues: {
                privatePlayerMode: { alwaysAsk: {} },
                overlayInteracted: false,
            },
            /** @type {import('../types/duckplayer.ts').UserValues} */
            setUserValues: {
                privatePlayerMode: { enabled: {} },
                overlayInteracted: false,
            },
        };
        this.mocks.defaultResponses(this.defaults);
    }

    /**
     * This ensures we can choose when to apply mocks based on the platform
     * @param {URLSearchParams} urlParams
     * @return {Promise<void>}
     */
    async openPage(urlParams) {
        const url = 'https://www.youtube-nocookie.com' + '?' + urlParams.toString();
        await this.mocks.install();
        await this.installYoutubeMocks(urlParams);
        // construct the final url
        await this.page.goto(url);
    }

    async reducedMotion() {
        await this.page.emulateMedia({ reducedMotion: 'reduce' });
    }

    playerIsEnabled() {
        this.mocks.defaultResponses({
            ...this.defaults,
            initialSetup: {
                ...this.defaults.initialSetup,
                userValues: {
                    privatePlayerMode: { enabled: {} },
                    overlayInteracted: false,
                },
            },
        });
    }

    /**
     * @param {{ state: 'enabled' | 'disabled' }} setting
     */
    pipSettingIs(setting) {
        const clone = structuredClone(this.defaults);
        clone.initialSetup.settings.pip = setting;
        this.mocks.defaultResponses(clone);
    }

    /**
     * @param {{ state: 'enabled' | 'disabled' }} setting
     */
    focusModeSettingIs(setting) {
        const clone = structuredClone(this.defaults);
        clone.initialSetup.settings.focusMode = setting;
        this.mocks.defaultResponses(clone);
    }

    /**
     * We don't need to actually load the content for these tests.
     * By mocking the response, we make the tests about 10x faster and also ensure they work offline.
     * @param {URLSearchParams} urlParams
     * @return {Promise<void>}
     */
    async installYoutubeMocks(urlParams) {
        await this.page.route('https://www.youtube-nocookie.com/**', (route, req) => {
            const url = new URL(req.url());
            if (url.pathname.startsWith('/embed')) {
                return route.continue();
            }
            // try to serve assets, but change `/` to 'index'
            let filepath = url.pathname;
            if (filepath === '/') filepath = 'index.html';

            return route.fulfill({
                status: 200,
                path: join(this.basePath, filepath),
            });
        });

        // the iframe
        await this.page.route('https://www.youtube-nocookie.com/embed/**', (request) => {
            if (urlParams.get('videoID') === 'UNSUPPORTED') {
                return request.fulfill({
                    status: 200,
                    body: html.unsupported,
                    contentType: 'text/html',
                });
            }

            if (urlParams.get('videoID') === 'SIGN_IN_REQUIRED') {
                return request.fulfill({
                    status: 200,
                    body: html.signInRequired,
                    contentType: 'text/html',
                });
            }

            const mp4VideoPlaceholderAsDataURI =
                'data:video/mp4;base64,AAAAHGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAwFtZGF0AAACogYF//+b3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE1MiByMjg1NCBlMjA5YTFjIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAxNyAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzowMTMzIHN1Ym1lPTcgcHN5PTEgcHN5X3JkPTEuMDA6MC4wMCBtaXhlZF9yZWY9MSBtZV9yYW5nZT0xNiBjaHJvbWFfbWU9MSB0cmVsbGlzPTEgOHg4ZGN0PTEgY3FtPTAgZGVhZHpvbmU9MjEsMTEgZmFzdF9wc2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9LTIgdGhyZWFkcz02MyBsb29rYWhlYWRfdGhyZWFkcz0yIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTMgYl9weXJhbWlkPTIgYl9hZGFwdD1xLTIgYl9iaWFzPTAgZGlyZWN0PTEgd2VpZ2h0Yj0xIG9wZW5fZ29wPTAgd2VpZ2h0cD0yIGtleWludD0yNTAga2V5aW50X21pbj0yNSBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmM9bG9va2FoZWFkIG1idHJlZT0xIGNyZj0yMy4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCB2YnY9MCBjbG9zZWRfZ29wPTAgY3V0X3Rocm91Z2g9MCAnbm8tZGlndHMuanBnLTFgcC1mbHWinS3SlB8AP0AAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABSAAAAAAAAAAAAAAAAAAABBZHJ0AAAAAAAAAA==';
            return request.fulfill({
                status: 200,
                contentType: 'text/html',
                body: `
                <html>
                    <head>
                    <title>${MOCK_VIDEO_TITLE}</title>
                    <style>
                        html, body {
                            margin: 0;
                            padding: 0;
                            height: 100%;
                            width: 100%;
                            background: black;
                            color: white;
                            display: grid;
                            align-items: center;
                            justify-items: center;
                        }
                        .ytp-pip-button {
                            -webkit-appearance: none;
                            border: 0;
                            box-shadow: none;
                            background: green;
                            display: none;
                        }
                    </style>
                    </head>
                    <body>Video Embed
                        <div id="player">
                            <video src="${mp4VideoPlaceholderAsDataURI}"></video>
                            <button class="ytp-pip-button">PIP</button>
                        </div>
                    </body>
                </html>`,
            });
        });

        // any navigations to actual youtube
        await this.page.route('https://www.youtube.com/**', (request) => {
            return request.fulfill({
                status: 200,
                body: 'youtube watch',
            });
        });
    }

    /**
     * @param {string} [videoID]
     * @returns {Promise<void>}
     */
    async openWithVideoID(videoID = MOCK_VIDEO_ID) {
        const params = new URLSearchParams({ videoID });
        await this.openPage(params);
    }

    /**
     * @param {import('../types/duckplayer.ts').YouTubeError} [youtubeError]
     * @param {string} [videoID]
     * @param {string} [locale]
     * @returns {Promise<void>}
     */
    async openWithYouTubeError(youtubeError = 'unknown', videoID = 'e90eWYPNtJ8', locale = 'en') {
        const params = new URLSearchParams({ youtubeError, videoID, customError: 'enabled', focusMode: 'disabled', locale });
        await this.openPage(params);
    }

    async openWithException() {
        const params = new URLSearchParams({ willThrow: String(true) });
        await this.openPage(params);
    }

    /**
     * @param {string} [videoID]
     * @returns {Promise<void>}
     */
    async openWithoutFocusMode(videoID = MOCK_VIDEO_ID) {
        const params = new URLSearchParams({ videoID, focusMode: 'disabled' });
        await this.openPage(params);
    }

    async showsErrorMessage() {
        await expect(this.page.locator('body')).toContainText('Something went wrong!');
    }

    /**
     * @param {string} timestamp
     * @param {string} [videoID]
     * @returns {Promise<void>}
     */
    async openWithTimestamp(timestamp, videoID = MOCK_VIDEO_ID) {
        const params = new URLSearchParams(Object.entries({ videoID, t: timestamp }));
        await this.openPage(params);
    }

    /**
     * @param {string} [videoID]
     * @returns {Promise<void>}
     */
    async hasLoadedIframe(videoID = MOCK_VIDEO_ID) {
        const url = this.platform.name === 'ios' ? youtubeEmbedIOS(videoID) : youtubeEmbed(videoID);

        const expected = new URL(url);
        await expect(this.page.locator('iframe')).toHaveAttribute('src', expected.toString());
    }

    async videoHasFocus() {
        await expect(this.page.frameLocator('iframe').locator('video')).toBeVisible();
        await expect(this.page.locator('body')).toHaveAttribute('data-video-state', 'loaded+focussed');
    }

    async hasPipButton() {
        await this.page.frameLocator('iframe').getByRole('button', { name: 'PIP' }).click();
    }

    async pipButtonIsAbsent() {
        const count = await this.page.frameLocator('iframe').getByRole('button', { name: 'PIP' }).count();
        expect(count).toBe(0);
    }

    /**
     * @param {'on'|'off'} focusModeValue
     */
    async focusModeIs(focusModeValue) {
        await expect(this.page.getByRole('document')).toHaveAttribute('data-focus-mode', focusModeValue);
    }

    async focusModeIsAbsent() {
        await expect(this.page.getByRole('document')).not.toHaveAttribute('data-focus-mode');
    }

    async hasTheSameTitleAsEmbed() {
        const expected = 'Duck Player - Embedded Video';

        // verify initial
        await this.page.waitForFunction((expected) => {
            return document.title === expected;
        }, expected);
    }

    /**
     * Asserts that the iframe is loaded with the additional 'start' param
     * @param {string} seconds
     * @param {string} [videoID]
     * @returns {Promise<void>}
     */
    async videoStartsAtTimestamp(seconds, videoID = MOCK_VIDEO_ID) {
        // construct the expected url
        const url = this.platform.name === 'ios' ? youtubeEmbedIOS(videoID) : youtubeEmbed(videoID);
        const youtubeSrc = new URL(url);

        youtubeSrc.searchParams.set('start', seconds);

        const expected = youtubeSrc.toString();

        // verify that the iframe src contains the timestamp
        await expect(this.page.locator('iframe')).toHaveAttribute('src', expected);
    }

    /**
     *
     * @param {string} text
     */
    async hasShownErrorMessage(text = 'ERROR: Invalid video id') {
        await expect(this.page.getByText(text)).toBeVisible();
    }

    async hasNotAddedIframe() {
        await expect(this.page.locator('iframe')).toHaveCount(0);
    }

    async toolbarIsVisible() {
        await this.page.getByText('Always open YouTube videos here').waitFor({ state: 'visible' });
    }

    async toolbarIsHidden() {
        await this.page.getByText('Always open YouTube videos here').waitFor({ state: 'hidden' });
    }

    async infoTooltipIsShowsOnFocus() {
        await this.page.getByLabel('Info').hover();
        await expect(this.page.getByRole('tooltip')).toBeVisible();
    }

    async infoTooltipHides() {
        await this.page.locator('body').hover();
        await expect(this.page.getByRole('tooltip')).toBeHidden();
    }

    async opensSettingsInNewTab() {
        const expected = 'duck://settings/duckplayer';
        const openSettings = this.page.getByRole('link', { name: 'Open Settings' });
        expect(await openSettings.getAttribute('href')).toEqual(expected);
        expect(await openSettings.getAttribute('target')).toEqual('_blank');
    }

    async opensInYoutube() {
        await this.build.switch({
            windows: async () => {
                const failure = new Promise((resolve) => {
                    this.page.context().on('requestfailed', (f) => {
                        resolve(f.url());
                    });
                });
                await this.page.getByRole('button', { name: 'Watch on YouTube' }).click();
                expect(await failure).toEqual('duck://player/openInYoutube?v=VIDEO_ID');
            },
            apple: async () => {
                const nextNavigation = new Promise((resolve) => {
                    this.page.context().on('request', (f) => {
                        resolve(f.url());
                    });
                });
                await this.page.getByRole('button', { name: 'Watch on YouTube' }).click();
                expect(await nextNavigation).toEqual('https://www.youtube.com/watch?v=VIDEO_ID');
            },
        });
    }

    async opensInYoutubeFromError({ videoID = 'UNSUPPORTED' }) {
        const action = () => this.page.frameLocator('#player').getByRole('link', { name: 'Watch on YouTube' }).click();
        await this.build.switch({
            windows: async () => {
                const failure = new Promise((resolve) => {
                    this.page.context().on('requestfailed', (f) => {
                        resolve(f.url());
                    });
                });
                await action();
                expect(await failure).toEqual(`duck://player/openInYoutube?v=${videoID}`);
            },
            apple: async () => {
                if (this.platform.name === 'ios') {
                    // todo: why does this not work on ios??
                    await action();
                    return;
                }
                await action();
                await this.page.waitForURL(`https://www.youtube.com/watch?v=${videoID}`);
            },
            android: async () => {
                // const failure = new Promise(resolve => {
                //     this.page.context().on('requestfailed', f => {
                //         resolve(f.url())
                //     })
                // })
                // todo: why does this not work on android?
                await action();
                // expect(await failure).toEqual(`duck://player/openInYoutube?v=${videoID}`)
            },
        });
    }

    async opensDuckPlayerYouTubeLinkFromError({ videoID = 'UNSUPPORTED' }) {
        const action = () => this.page.getByRole('button', { name: 'Watch on YouTube' }).click();
        await this.build.switch({
            windows: async () => {
                const failure = new Promise((resolve) => {
                    this.page.context().on('requestfailed', (f) => {
                        resolve(f.url());
                    });
                });
                await action();
                expect(await failure).toEqual(`duck://player/openInYoutube?v=${videoID}`);
            },
            apple: async () => {
                if (this.platform.name === 'ios') {
                    // todo: why does this not work on ios??
                    await action();
                    return;
                }
                await action();
                await this.page.waitForURL(`https://www.youtube.com/watch?v=${videoID}`);
            },
            android: async () => {
                // const failure = new Promise(resolve => {
                //     this.page.context().on('requestfailed', f => {
                //         resolve(f.url())
                //     })
                // })
                // todo: why does this not work on android?
                await action();
                // expect(await failure).toEqual(`duck://player/openInYoutube?v=${videoID}`)
            },
        });
    }

    /**
     * @return {Promise<void>}
     */
    async enabledViaSettings() {
        await this.mocks.simulateSubscriptionMessage('onUserValuesChanged', {
            privatePlayerMode: {
                enabled: {},
            },
            overlayInteracted: false,
        });
    }

    async checkboxWasChecked() {
        await this.page.locator('[type=checkbox]').isChecked();
    }

    /**
     * @return {Promise<void>}
     */
    async didReceiveFirstSettingsUpdate() {
        await this.mocks.waitForCallCount({ count: 1, method: 'initialSetup' });
    }

    async toggleAlwaysOpenSetting() {
        await this.page.getByLabel('Always open YouTube videos here').click();
    }

    async settingsAreVisible() {
        await expect(this.page.getByRole('button', { name: 'Watch on YouTube' })).toBeVisible();
    }

    async sentUpdatedSettings() {
        const calls = await this.mocks.waitForCallCount({ count: 1, method: 'setUserValues' });
        expect(calls[0].payload).toMatchObject({
            context: 'specialPages',
            featureName: 'duckPlayerPage',
            method: 'setUserValues',
            params: {
                overlayInteracted: false,
                privatePlayerMode: {
                    enabled: {},
                },
            },
        });
    }

    /**
     * @param {import('../types/duckplayer.ts').TelemetryEvent} evt
     */
    async didSendTelemetry(evt) {
        const events = await this.mocks.waitForCallCount({ method: 'telemetryEvent', count: 1 });
        expect(events).toStrictEqual([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'duckPlayerPage',
                    method: 'telemetryEvent',
                    params: evt,
                },
            },
        ]);
    }

    async withStorageValues() {
        await this.page.evaluate(() => {
            localStorage.setItem('foo', 'bar');
            localStorage.setItem('yt-player-other', 'baz');
        });
    }

    async storageClearedAfterReload() {
        await this.page.reload();
        const storaget = await this.page.evaluate(() => localStorage);
        const keys = Object.keys(storaget);
        expect(keys).toStrictEqual(['yt-player-other']);
    }

    /**
     * We test the fully built artifacts, so for each test run we need to
     * select the correct HTML file.
     * @return {string}
     */
    get basePath() {
        return this.build.switch({
            windows: () => '../build/windows/pages/duckplayer',
            android: () => '../build/android/pages/duckplayer',
            apple: () => '../Sources/ContentScopeScripts/dist/pages/duckplayer',
        });
    }

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new DuckPlayerPage(page, build, platformInfo);
    }

    async allowsPopups() {
        const expected = 'allow-popups allow-scripts allow-same-origin allow-popups-to-escape-sandbox';
        await expect(this.page.locator('iframe')).toHaveAttribute('sandbox', expected);
    }

    async openSettings() {
        const { page } = this;
        await page.getByLabel('Open Settings').click();
    }

    async didOpenMobileSettings() {
        await this.build.switch({
            android: async () => {
                await this.mocks.waitForCallCount({ count: 1, method: 'openSettings' });
            },
            apple: async () => {
                await this.mocks.waitForCallCount({ count: 1, method: 'openSettings' });
            },
        });
    }

    async didOpenSettings() {
        await this.mocks.waitForCallCount({ count: 1, method: 'openSettings' });
    }

    async didOpenInfo() {
        await this.mocks.waitForCallCount({ count: 1, method: 'openInfo' });
    }

    async didWatchOnYoutube() {}

    async watchOnYoutube() {
        const { page } = this;
        await page.getByRole('button', { name: 'Watch on YouTube' }).click();
    }

    async openInfo() {
        const { page } = this;
        await page.getByRole('button', { name: 'Open Info' }).click();
    }

    /* Aria Snapshots */
    async didShowGenericError() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Duck Player can’t load this video" [level=1]
            - paragraph: This video can’t be viewed outside of YouTube.
            - paragraph: You can still watch this video on YouTube, but without the added privacy of Duck Player.
          `);
    }

    async didShowGenericErrorInSpanish() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Duck Player no puede cargar este vídeo" [level=1]
            - paragraph: Este vídeo no se puede ver fuera de YouTube.
            - paragraph: Sigues pudiendo ver este vídeo en YouTube, pero sin la privacidad adicional que ofrece Duck Player.
          `);
    }

    async didShowAgeRestrictedError() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Sorry, this video is age-restricted" [level=1]
            - paragraph: To watch age-restricted videos, you need to sign in to YouTube to verify your age.
            - paragraph: You can still watch this video, but you’ll have to sign in and watch it on YouTube without the added privacy of Duck Player.
          `);
    }

    async didShowAgeRestrictedErrorInSpanish() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Lo sentimos, este vídeo está restringido por edad" [level=1]
            - paragraph: Para ver vídeos con restricción de edad, necesitas iniciar sesión en YouTube para verificar tu edad.
            - paragraph: Todavía puedes ver este vídeo, pero tendrás que iniciar sesión y verlo en YouTube sin la privacidad adicional de Duck Player.
          `);
    }

    async didShowNoEmbedError() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Sorry, this video can only be played on YouTube" [level=1]
            - paragraph: The creator of this video has chosen not to allow it to be viewed on other sites.
            - paragraph: You can still watch it on YouTube, but without the added privacy of Duck Player.
          `);
    }

    async didShowNoEmbedErrorInSpanish() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Lo sentimos, este vídeo solo se puede reproducir en YouTube" [level=1]
            - paragraph: El creador de este vídeo ha decidido no permitir que se vea en otros sitios.
            - paragraph: Sigues pudiendo verlo en YouTube, pero sin la privacidad adicional que ofrece Duck Player.
          `);
    }

    async didShowSignInRequiredError() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Sorry, YouTube thinks you’re a bot" [level=1]
            - paragraph: This can happen if you’re using a VPN. Try turning the VPN off or switching server locations and reloading this page.
            - paragraph: If that doesn’t work, you’ll have to sign in and watch this video on YouTube without the added privacy of Duck Player.
          `);
    }

    async didShowSignInRequiredErrorInSpanish() {
        await expect(this.page.getByTestId('YouTubeErrorContent')).toMatchAriaSnapshot(`
            - heading "Lo sentimos, YouTube piensa que eres un bot" [level=1]
            - paragraph: Esto puede ocurrir si estás usando una VPN. Intenta desactivar la VPN o cambiar la ubicación del servidor y recarga la página.
            - paragraph: Si eso no funciona, tendrás que iniciar sesión y ver el vídeo en YouTube sin la privacidad adicional que ofrece Duck Player.
          `);
    }
}
