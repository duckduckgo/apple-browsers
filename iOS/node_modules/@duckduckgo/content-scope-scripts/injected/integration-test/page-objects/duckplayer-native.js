import { readFileSync } from 'fs';
import { expect } from '@playwright/test';
import { perPlatform } from '../type-helpers.mjs';
import { ResultsCollector } from './results-collector.js';

/**
 * @import { PageType } from '../../src/features/duckplayer-native/messages.js'
 * @typedef {"default" | "incremental-dom" | "age-restricted-error" | "sign-in-error" | "no-embed-error" | "unknown-error"} PlayerPageVariants
 */

// eslint-disable-next-line @typescript-eslint/no-unused-vars
const configFiles = /** @type {const} */ (['native.json']);

const defaultInitialSetup = {
    locale: 'en',
};

const featureName = 'duckPlayerNative';

export class DuckPlayerNative {
    /** @type {Partial<Record<PageType, string>>} */
    pages = {
        YOUTUBE: '/duckplayer-native/pages/player.html',
        NOCOOKIE: '/duckplayer-native/pages/player.html',
    };

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("../type-helpers.mjs").Build} build
     * @param {import("@duckduckgo/messaging/lib/test-utils.mjs").PlatformInfo} platform
     */
    constructor(page, build, platform) {
        this.page = page;
        this.build = build;
        this.platform = platform;
        this.isMobile = platform.name === 'android' || platform.name === 'ios';
        this.collector = new ResultsCollector(page, build, platform);
        this.collector.withMockResponse({
            initialSetup: defaultInitialSetup,
            onCurrentTimestamp: {},
        });
        this.collector.withUserPreferences({
            messageSecret: 'ABC',
            javascriptInterface: 'javascriptInterface',
            messageCallback: 'messageCallback',
        });
        page.on('console', (msg) => {
            console.log(msg.type(), msg.text());
        });
    }

    async reducedMotion() {
        await this.page.emulateMedia({ reducedMotion: 'reduce' });
    }

    /**
     * @param {object} [params]
     * @param {string} [params.videoID]
     */
    async gotoYouTubePage(params = {}) {
        await this.gotoPage('YOUTUBE', params);
    }

    async gotoNoCookiePage() {
        await this.gotoPage('NOCOOKIE', {});
    }

    async gotoAgeRestrictedErrorPage() {
        await this.gotoPage('NOCOOKIE', { variant: 'age-restricted-error' });
    }

    async gotoNoEmbedErrorPage() {
        await this.gotoPage('NOCOOKIE', { variant: 'no-embed-error' });
    }

    async gotoUnknownErrorPage() {
        await this.gotoPage('NOCOOKIE', { variant: 'unknown-error' });
    }

    async gotoSignInErrorPage() {
        await this.gotoPage('NOCOOKIE', { variant: 'sign-in-error' });
    }

    async gotoSERP() {
        await this.gotoPage('SERP', {});
    }

    /**
     * @param {PageType} pageType
     * @param {object} [params]
     * @param {PlayerPageVariants} [params.variant]
     * @param {string} [params.videoID]
     */
    async gotoPage(pageType, params = {}) {
        await this.withPageType(pageType);

        const defaultVariant = this.isMobile ? 'mobile' : 'default';
        const { variant = defaultVariant, videoID = '123' } = params;
        const urlParams = new URLSearchParams([
            ['v', videoID],
            ['variant', variant],
        ]);

        const page = this.pages[pageType];

        await this.page.goto(page + '?' + urlParams.toString());
    }

    /**
     * @param {object} [params]
     * @param {configFiles[number]} [params.json="native"] - default is settings for localhost
     * @param {string} [params.locale] - optional locale
     */
    async withRemoteConfig(params = {}) {
        const { json = 'native.json', locale = 'en' } = params;

        await this.collector.setup({ config: loadConfig(json), locale });
    }

    /**
     * @param {PageType} pageType
     * @return {Promise<void>}
     */
    async withPageType(pageType) {
        const initialSetup = this.collector.mockResponses?.initialSetup || defaultInitialSetup;

        await this.collector.updateMockResponse({
            initialSetup: { pageType, ...initialSetup },
        });
    }

    /**
     * @param {boolean} playbackPaused
     * @return {Promise<void>}
     */
    async withPlaybackPaused(playbackPaused = true) {
        const initialSetup = this.collector.mockResponses.initialSetup || defaultInitialSetup;

        await this.collector.updateMockResponse({
            initialSetup: { playbackPaused, ...initialSetup },
        });
    }

    /**
     * @param {string} name
     * @param {Record<string, any>} payload
     */
    async simulateSubscriptionMessage(name, payload) {
        await this.collector.simulateSubscriptionMessage(featureName, name, payload);
    }

    /**
     * Helper for creating an instance per platform
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new DuckPlayerNative(page, build, platformInfo);
    }

    /**
     * @return {Promise<string>}
     */
    requestWillFail() {
        return new Promise((resolve, reject) => {
            // on windows it will be a failed request
            const timer = setTimeout(() => {
                reject(new Error('timed out'));
            }, 5000);
            this.page.on('framenavigated', (req) => {
                clearTimeout(timer);
                resolve(req.url());
            });
        });
    }

    /* Subscriptions */

    /**
     * @param {object} options
     */
    async sendOnMediaControl(options = { pause: true }) {
        await this.simulateSubscriptionMessage('onMediaControl', options);
    }

    /**
     * @param {object} options
     */
    async sendOnSerpNotify(options = {}) {
        await this.simulateSubscriptionMessage('onSerpNotify', options);
    }

    /**
     * @param {object} options
     */
    async sendOnMuteAudio(options = { mute: true }) {
        await this.simulateSubscriptionMessage('onMuteAudio', options);
    }

    /**
     * @param {PageType} pageType
     */
    async sendURLChanged(pageType) {
        await this.simulateSubscriptionMessage('onUrlChanged', { pageType });
    }

    /* Messaging assertions */

    async didSendInitialHandshake() {
        const messages = await this.collector.waitForMessage('initialSetup');
        expect(messages).toMatchObject([
            {
                payload: {
                    context: this.collector.messagingContextName,
                    featureName,
                    method: 'initialSetup',
                    params: {},
                },
            },
        ]);
    }

    async didSendCurrentTimestamp() {
        const messages = await this.collector.waitForMessage('onCurrentTimestamp');
        expect(messages).toMatchObject([
            {
                payload: {
                    context: this.collector.messagingContextName,
                    featureName,
                    method: 'onCurrentTimestamp',
                    params: { timestamp: '0' },
                },
            },
        ]);
    }

    /* Thumbnail Overlay assertions */

    async didShowOverlay() {
        await this.page.locator('ddg-video-thumbnail-overlay-mobile').waitFor({ state: 'visible', timeout: 1000 });
    }

    async didShowLogoInOverlay() {
        await this.page.locator('ddg-video-thumbnail-overlay-mobile .logo').waitFor({ state: 'visible', timeout: 1000 });
    }

    async overlayIsUnique() {
        const count = await this.page.locator('ddg-video-thumbnail-overlay-mobile').count();
        expect(count).toBe(1);
    }

    async clickOnOverlay() {
        await this.page.locator('ddg-video-thumbnail-overlay-mobile').click();
    }

    async didDismissOverlay() {
        await this.page.locator('ddg-video-thumbnail-overlay-mobile').waitFor({ state: 'hidden', timeout: 1000 });
    }

    async didSendOverlayDismissalMessage() {
        const messages = await this.collector.waitForMessage('didDismissOverlay');
        expect(messages).toMatchObject([
            {
                payload: {
                    context: this.collector.messagingContextName,
                    featureName,
                    method: 'didDismissOverlay',
                    params: {},
                },
            },
        ]);
    }

    /* Custom Error assertions */

    async didShowAgeRestrictedError() {
        await expect(this.page.locator('ddg-video-error')).toMatchAriaSnapshot(`
            - heading "Sorry, this video is age-restricted" [level=1]
            - paragraph: To watch age-restricted videos, you need to sign in to YouTube to verify your age.
            - paragraph: You can still watch this video, but you’ll have to sign in and watch it on YouTube without the added privacy of Duck Player.
          `);
    }

    async didShowNoEmbedError() {
        await expect(this.page.locator('ddg-video-error')).toMatchAriaSnapshot(`
            - heading "Sorry, this video can only be played on YouTube" [level=1]
            - paragraph: The creator of this video has chosen not to allow it to be viewed on other sites.
            - paragraph: You can still watch it on YouTube, but without the added privacy of Duck Player.
          `);
    }

    async didShowUnknownError() {
        await expect(this.page.locator('ddg-video-error')).toMatchAriaSnapshot(`
            - heading "Duck Player can’t load this video" [level=1]
            - paragraph: This video can’t be viewed outside of YouTube.
            - paragraph: You can still watch this video on YouTube, but without the added privacy of Duck Player.
          `);
    }

    async didShowSignInError() {
        await expect(this.page.locator('ddg-video-error')).toMatchAriaSnapshot(`
            - heading "Sorry, YouTube thinks you’re a bot" [level=1]
            - paragraph: This can happen if you’re using a VPN. Try turning the VPN off or switching server locations and reloading this page.
            - paragraph: If that doesn’t work, you’ll have to sign in and watch this video on YouTube without the added privacy of Duck Player.
          `);
    }

    /**
     * @param {number} numberOfCalls - Number of times the message should be received
     */
    async didSendDuckPlayerScriptsReady(numberOfCalls = 1) {
        const expectedMessage = {
            payload: {
                context: this.collector.messagingContextName,
                featureName,
                method: 'onDuckPlayerScriptsReady',
                params: {},
            },
        };
        const expectedMessages = Array(numberOfCalls).fill(expectedMessage);
        const actualMessages = await this.collector.waitForMessage('onDuckPlayerScriptsReady');

        expect(actualMessages).toMatchObject(expectedMessages);
    }
}

/**
 * @param {configFiles[number]} name
 * @return {Record<string, any>}
 */
function loadConfig(name) {
    return JSON.parse(readFileSync(`./integration-test/test-pages/duckplayer-native/config/${name}`, 'utf8'));
}
