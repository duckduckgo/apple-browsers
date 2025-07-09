import { Mocks } from '../../../shared/mocks.js';
import { perPlatform } from 'injected/integration-test/type-helpers.mjs';
import { expect } from '@playwright/test';
import { join } from 'node:path';

/**
 * @typedef {import('injected/integration-test/type-helpers.mjs').Build} Build
 * @typedef {import('injected/integration-test/type-helpers.mjs').PlatformInfo} PlatformInfo
 */

export class OnboardingPage {
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
            featureName: 'onboarding',
            env: 'development',
        });
        this.page.on('console', console.log);
        this.defaultResponses = {
            requestSetAsDefault: {},
            requestDockOptIn: {},
            requestImport: { enabled: true },
            stepCompleted: {},
            setAdBlocking: {},
            reportPageException: {},
            init: {
                stepDefinitions: {
                    systemSettings: {
                        // this 'dock' is not part of the default
                        rows: ['dock', 'import', 'default-browser'],
                    },
                },
                env: 'development',
            },
        };
        // default mocks - just enough to render the first page without error
        this.mocks.defaultResponses(this.defaultResponses);
    }

    withInitData(data) {
        this.mocks.defaultResponses({
            ...this.defaultResponses,
            init: data,
        });
    }

    withMockData(data) {
        this.mocks.defaultResponses({
            ...this.defaultResponses,
            ...data,
        });
    }

    /**
     * Opens a page with optional parameters.
     * This method ensures that mocks are installed and routes are set up before navigating to the page.
     *
     * @param {Object} [params] - Optional parameters for opening the page.
     * @param {'app' | 'components'} [params.env] - Optional parameters for opening the page.
     * @param {import('../app/types.js').Step['id']} [params.page] - Optional start page
     * @param {boolean} [params.willThrow] - Optional flag to simulate an exception
     */
    async openPage({ env = 'app', page = 'welcome', willThrow = false } = {}) {
        await this.mocks.install();
        const searchParams = new URLSearchParams({ env, page, debugState: 'true', willThrow: String(willThrow) });
        await this.page.route('/**', (route, req) => {
            const url = new URL(req.url());
            // try to serve assets, but change `/` to 'index'
            let filepath = url.pathname;
            if (filepath === '/') filepath = 'index.html';

            return route.fulfill({
                status: 200,
                path: join(this.basePath, filepath),
            });
        });
        await this.page.goto('/' + '?' + searchParams.toString());
    }

    async skipsOnboarding() {
        await this.page.getByTestId('skip').click({
            clickCount: 5,
        });
    }

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new OnboardingPage(page, build, platformInfo);
    }

    async reducedMotion() {
        await this.page.emulateMedia({ reducedMotion: 'reduce' });
    }

    async darkMode() {
        await this.page.emulateMedia({ colorScheme: 'dark' });
    }

    async didSendStepCompletedMessages() {
        const calls = await this.mocks.outgoing({ names: ['stepCompleted'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'stepCompleted',
                    params: { id: 'welcome' },
                },
            },
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'stepCompleted',
                    params: { id: 'getStarted' },
                },
            },
        ]);
    }

    /**
     * We test the fully built artifacts, so for each test run we need to
     * select the correct HTML file.
     * @return {string}
     */
    get basePath() {
        return this.build.switch({
            windows: () => '../build/windows/pages/onboarding',
            apple: () => '../Sources/ContentScopeScripts/dist/pages/onboarding',
        });
    }

    async choseToStartBrowsing() {
        await this.page.getByRole('button', { name: 'Start Browsing' }).click();
    }

    async didDismissToSearch() {
        await this.mocks.waitForCallCount({ method: 'dismissToAddressBar', count: 1, timeout: 500 });
    }

    async didDismissToSettings() {
        await this.page.getByRole('link', { name: 'Settings' }).click();
        await this.mocks.waitForCallCount({ method: 'dismissToSettings', count: 1, timeout: 500 });
    }

    async skippedCurrent() {
        await this.page.getByRole('button', { name: 'Skip' }).click();
    }

    /**
     * @param {boolean} adBlockingEnabled
     */
    async checkYouTubeText(adBlockingEnabled) {
        const expectedText = adBlockingEnabled ? 'Watch YouTube ad-free' : 'Play YouTube without targeted ads';
        await expect(this.page.getByRole('table')).toContainText(expectedText);
    }

    async makeDefault() {
        const { page } = this;
        await page.getByRole('button', { name: 'Make Default' }).click();
        await page.getByRole('img', { name: 'Completed Action' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['requestSetAsDefault'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'requestSetAsDefault',
                    params: {},
                },
            },
        ]);
    }

    async importUserData() {
        const { page } = this;
        await page.getByRole('button', { name: 'Import' }).click();
        await page.getByRole('img', { name: 'Completed Action' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['requestImport'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'requestImport',
                    params: {},
                },
            },
        ]);
    }

    async importUserDataFailedGracefully() {
        const { page } = this;
        await page.getByRole('button', { name: 'Import Now', exact: true }).click();
        await page.getByRole('button', { name: 'Import', exact: true }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['requestImport'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'requestImport',
                    params: {},
                },
            },
        ]);
    }

    async showBookmarksBar() {
        const { page } = this;
        await page.getByRole('button', { name: 'Show Bookmarks Bar' }).click();
        await page.getByRole('img', { name: 'Completed Action' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['setBookmarksBar'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setBookmarksBar',
                    params: { enabled: true },
                },
            },
        ]);
    }

    async skippedBookmarksBar() {
        await this.skippedCurrent();
        await this.page.getByRole('switch', { name: 'Show Bookmarks Bar' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['setBookmarksBar'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setBookmarksBar',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async skippedSessionRestore() {
        await this.skippedCurrent();
        await this.page.getByRole('switch', { name: 'Enable Session Restore' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['setSessionRestore'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setSessionRestore',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async skippedShowHomeButton() {
        await this.skippedCurrent();
        await this.page.getByRole('switch', { name: 'Show Home Button' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['setShowHomeButton'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setShowHomeButton',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async canToggleBookmarksBar() {
        const { page } = this;
        const input = page.getByLabel('Bookmarks Bar');

        // control: ensure we're starting in the 'off' state
        expect(await input.isChecked()).toBe(false);

        // now turn it on
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(true);

        // and then back off
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(false);

        // now check the outgoing messages
        const calls = await this.mocks.outgoing({ names: ['setBookmarksBar'] });
        expect(calls).toMatchObject([
            // initial call from skipping:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setBookmarksBar',
                    params: { enabled: false },
                },
            },
            // subsequent calls from toggling:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setBookmarksBar',
                    params: { enabled: true },
                },
            },
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setBookmarksBar',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async restoreSession() {
        const { page } = this;
        await page.getByRole('button', { name: 'Enable Session Restore' }).click();
        await page.getByRole('img', { name: 'Completed Action' }).waitFor();
        const calls = await this.mocks.outgoing({ names: ['setSessionRestore'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setSessionRestore',
                    params: { enabled: true },
                },
            },
        ]);
    }

    async canToggleRestoreSession() {
        const { page } = this;
        const input = page.getByLabel('Enable Session Restore');

        // control: ensure we're starting in the 'off' state
        expect(await input.isChecked()).toBe(false);

        // now turn it on
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(true);

        // and then back off
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(false);

        // now check the outgoing messages
        const calls = await this.mocks.outgoing({ names: ['setSessionRestore'] });
        expect(calls).toMatchObject([
            // initial call from skipping:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setSessionRestore',
                    params: { enabled: false },
                },
            },
            // subsequent calls from toggling:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setSessionRestore',
                    params: { enabled: true },
                },
            },
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setSessionRestore',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async canToggleHomeButton() {
        const { page } = this;
        const input = page.getByLabel('Home Button');

        // control: ensure we're starting in the 'off' state
        expect(await input.isChecked()).toBe(false);

        // now turn it on
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(true);

        // and then back off
        await input.click();
        await page.waitForTimeout(100);
        expect(await input.isChecked()).toBe(false);

        // now check the outgoing messages
        const calls = await this.mocks.outgoing({ names: ['setShowHomeButton'] });
        expect(calls).toMatchObject([
            // initial call from skipping:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setShowHomeButton',
                    params: { enabled: false },
                },
            },
            // subsequent calls from toggling:
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setShowHomeButton',
                    params: { enabled: true },
                },
            },
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setShowHomeButton',
                    params: { enabled: false },
                },
            },
        ]);
    }

    async showHomeButton() {
        const { page } = this;
        await page.getByRole('button', { name: 'Show Home Button' }).click();
        await expect(page.getByRole('img', { name: 'Completed Action' })).toBeVisible();
        const calls = await this.mocks.outgoing({ names: ['setShowHomeButton'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setShowHomeButton',
                    params: { enabled: true },
                },
            },
        ]);
    }

    async enableEnhancedAdBlocking() {
        const { page } = this;
        await page.getByRole('button', { name: 'Turn on Enhanced Ad Blocking' }).click();
        await expect(page.getByRole('img', { name: 'Completed Action' })).toBeVisible();
        await this.didSetAdBlocking();
    }

    async enableYouTubeAdBlocking() {
        const { page } = this;
        await page.getByRole('button', { name: 'Block Ads' }).click();
        await expect(page.getByRole('img', { name: 'Completed Action' })).toBeVisible();
        await this.didSetAdBlocking();
    }

    async skipAdBlocking() {
        const { page } = this;
        await this.skippedCurrent();
        await page.getByRole('button', { name: 'Next' }).waitFor();
        await this.didSetAdBlocking({ enabled: false }); // important that setAdBlocking() is called when skipped so that native apps can fire a pixel
    }

    async skipYouTubeAdBlocking() {
        const { page } = this;
        await this.skippedCurrent();
        await page.getByRole('button', { name: 'Next' }).waitFor();
        await this.didSetAdBlocking({ enabled: false }); // important that setAdBlocking() is called when skipped so that native apps can fire a pixel
    }

    async didSetAdBlocking({ enabled = true } = {}) {
        const calls = await this.mocks.outgoing({ names: ['setAdBlocking'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'setAdBlocking',
                    params: { enabled },
                },
            },
        ]);
    }

    async startBrowsing() {
        const { page } = this;
        await page.getByRole('button', { name: 'Start Browsing' }).click();
        const calls = await this.mocks.outgoing({ names: ['dismissToAddressBar'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'dismissToAddressBar',
                    params: {},
                },
            },
        ]);
    }

    async hasAdditionalInformation() {
        const { page } = this;
        await expect(page.locator('h2')).toContainText('Make DuckDuckGo work just the way you want.');
    }

    async hasAdditionalInformationV3() {
        const { page } = this;
        await expect(page.locator('h2')).toContainText('Set things up just the way you want.');
    }

    async handlesFatalException() {
        const { page } = this;
        await expect(page.getByRole('heading')).toContainText('Something went wrong');
        const calls = await this.mocks.waitForCallCount({ method: 'reportPageException', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'reportPageException',
                    params: {
                        message: 'Simulated Exception',
                        id: 'welcome',
                    },
                },
            },
        ]);
    }

    async getStarted() {
        const { page } = this;
        await page.getByRole('button', { name: 'Get Started' }).click();
        await expect(page.getByLabel('Unlike other browsers,')).toContainText(
            'Unlike other browsers, DuckDuckGo comes with privacy by default',
        );
    }

    async didSendInitialHandshake() {
        const calls = await this.mocks.outgoing({ names: ['init'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'init',
                },
            },
        ]);
    }

    async keepInTaskbar() {
        const { page } = this;
        const locator = this.build.switch({
            apple: () => page.getByRole('button', { name: 'Keep in Dock' }),
            windows: () => page.getByRole('button', { name: 'Pin to Taskbar' }),
        });
        await locator.click();
        const calls = await this.mocks.waitForCallCount({ method: 'requestDockOptIn', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'onboarding',
                    method: 'requestDockOptIn',
                },
            },
        ]);
    }

    async completesOrderV2() {
        const { page } = this;
        await page.getByRole('button', { name: 'Get Started' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'See With Tracker Blocking' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'See With Duck Player' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'Next' }).click();

        const dockTitle = this.build.switch({
            windows: () => page.getByText('Keep DuckDuckGo in your Taskbar'),
            apple: () => page.getByText('Keep DuckDuckGo in your Dock'),
        });

        await dockTitle.waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Skip' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByText('Bring your stuff').waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Skip' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByText('Switch your default browser').waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Skip' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByLabel('Customize your experience').waitFor({ timeout: 1000 });
    }

    async completesOrderV2WithoutDock() {
        const { page } = this;
        await page.getByRole('button', { name: 'Get Started' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'See With Tracker Blocking' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'See With Duck Player' }).click();
        await page.getByRole('button', { name: 'Got It' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByText('Bring your stuff').waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Skip' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByText('Switch your default browser').waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Skip' }).click();
        await page.getByRole('button', { name: 'Next' }).click();
        await page.getByLabel('Customize your experience').waitFor({ timeout: 1000 });
    }

    async completesOrderV3() {
        const { page } = this;

        /* Welcome */
        await page.getByText('Welcome to DuckDuckGo').nth(1).waitFor({ timeout: 1000 });

        /* Get started */
        await page.getByText('Hi there').nth(1).waitFor({ timeout: 1500 });
        await page.getByRole('button', { name: 'Let’s Do It' }).click();

        /* Make default */
        await page.getByText('Protections activated').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Make DuckDuckGo Your Default' }).click();
        await page.getByText('Excellent!').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Next' }).click();

        /* System settings */
        await page.getByText('Let’s get you set up!').nth(1).waitFor({ timeout: 1000 });
        const dockButton = this.build.switch({
            windows: () => page.getByRole('button', { name: 'Pin to Taskbar' }),
            apple: () => page.getByRole('button', { name: 'Keep in Dock' }),
        });
        await dockButton.click();
        await page.getByRole('button', { name: 'Import' }).click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* Duckplayer */
        await page.getByText('Drowning in ads').nth(1).waitFor({ timeout: 1000 });
        await page.getByLabel('See Without Duck Player').click();
        await page.getByLabel('See With Duck Player').click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* Customize */
        await page.getByText('Let’s customize a few things').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Show Bookmarks Bar' }).click();
        await page.getByRole('button', { name: 'Enable Session Restore' }).click();
        await page.getByRole('button', { name: 'Show Home Button' }).click();
        await this.startBrowsing();
    }

    async completesOrderV3WithoutSettings() {
        const { page } = this;

        /* Welcome */
        await page.getByText('Welcome to DuckDuckGo').nth(1).waitFor({ timeout: 1000 });

        /* Get started */
        await page.getByText('Hi there').nth(1).waitFor({ timeout: 1500 });
        await page.getByRole('button', { name: 'Let’s Do It' }).click();

        /* Make default */
        await page.getByText('Protections activated').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Make DuckDuckGo Your Default' }).click();
        await page.getByText('Excellent!').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Next' }).click();

        /* Duckplayer */
        await page.getByText('Drowning in ads').nth(1).waitFor({ timeout: 1000 });
        await page.getByLabel('See Without Duck Player').click();
        await page.getByLabel('See With Duck Player').click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* Customize */
        await page.getByText('Let’s customize a few things').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Show Bookmarks Bar' }).click();
        await page.getByRole('button', { name: 'Enable Session Restore' }).click();
        await page.getByRole('button', { name: 'Show Home Button' }).click();
        await this.startBrowsing();
    }

    /**
     * @param {'ad-blocking'|'youtube-ad-blocking'} adBlockingId
     */
    async completesOrderV3WithAdBlockingEnabled(adBlockingId) {
        const { page } = this;

        /* Welcome */
        await page.getByText('Welcome to DuckDuckGo').nth(1).waitFor({ timeout: 1000 });

        /* Get started */
        await page.getByText('Hi there').nth(1).waitFor({ timeout: 1500 });
        await page.getByRole('button', { name: 'Let’s Do It' }).click();

        /* Make default */
        await page.getByText('Protections activated').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Make DuckDuckGo Your Default' }).click();
        await page.getByText('Excellent!').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Next' }).click();

        /* System settings */
        await page.getByText('Let’s get you set up!').nth(1).waitFor({ timeout: 1000 });
        const dockButton = this.build.switch({
            windows: () => page.getByRole('button', { name: 'Pin to Taskbar' }),
            apple: () => page.getByRole('button', { name: 'Keep in Dock' }),
        });
        await dockButton.click();
        await page.getByRole('button', { name: 'Import Now', exact: true }).click();
        await page
            .getByRole('button', {
                name: adBlockingId === 'youtube-ad-blocking' ? 'Block Ads' : 'Turn on Enhanced Ad Blocking',
                exact: true,
            })
            .click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* No Duck Player step as ad blocking was enabled */

        /* Customize */
        await page.getByText('Let’s customize a few things').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Show Bookmarks Bar' }).click();
        await page.getByRole('button', { name: 'Enable Session Restore' }).click();
        await page.getByRole('button', { name: 'Show Home Button' }).click();
        await this.startBrowsing();
    }

    async completesOrderV3WithAdBlockingDisabled() {
        const { page } = this;

        /* Welcome */
        await page.getByText('Welcome to DuckDuckGo').nth(1).waitFor({ timeout: 1000 });

        /* Get started */
        await page.getByText('Hi there').nth(1).waitFor({ timeout: 1500 });
        await page.getByRole('button', { name: 'Let’s Do It' }).click();

        /* Make default */
        await page.getByText('Protections activated').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Make DuckDuckGo Your Default' }).click();
        await page.getByText('Excellent!').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Next' }).click();

        /* System settings */
        await page.getByText('Let’s get you set up!').nth(1).waitFor({ timeout: 1000 });
        const dockButton = this.build.switch({
            windows: () => page.getByRole('button', { name: 'Pin to Taskbar' }),
            apple: () => page.getByRole('button', { name: 'Keep in Dock' }),
        });
        await dockButton.click();
        await page.getByRole('button', { name: 'Import Now', exact: true }).click();
        await page.getByRole('button', { name: 'Skip', exact: true }).click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* Duck Player */
        await page.getByText('Drowning in ads').nth(1).waitFor({ timeout: 1000 });
        await page.getByLabel('See Without Duck Player').click();
        await page.getByLabel('See With Duck Player').click();
        await page.getByRole('button', { name: 'Next' }).click();

        /* Customize */
        await page.getByText('Let’s customize a few things').nth(1).waitFor({ timeout: 1000 });
        await page.getByRole('button', { name: 'Show Bookmarks Bar' }).click();
        await page.getByRole('button', { name: 'Enable Session Restore' }).click();
        await page.getByRole('button', { name: 'Show Home Button' }).click();
        await this.startBrowsing();
    }
}
