import { Mocks } from '../../../shared/mocks.js';
import { perPlatform } from 'injected/integration-test/type-helpers.mjs';
import { join } from 'node:path';
import { expect } from '@playwright/test';
import { sampleData } from '../app/sampleData.js';

/**
 * @typedef {import('injected/integration-test/type-helpers.mjs').Build} Build
 * @typedef {import('injected/integration-test/type-helpers.mjs').PlatformInfo} PlatformInfo
 * @typedef {import('../types/release-notes.ts').UpdateMessage} UpdateMessage
 */

export class ReleaseNotesPage {
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
            featureName: 'release-notes',
            env: 'development',
        });
        this.page.on('console', console.log);
        // default mocks - just enough to render the first page without error
        this.mocks.defaultResponses({
            initialSetup: {
                env: 'development',
                locale: 'en',
            },
        });
    }

    /**
     * Opens a page with optional parameters.
     * This method ensures that mocks are installed and routes are set up before navigating to the page.
     *
     * @param {Object} [params] - Optional parameters for opening the page.
     * @param {'app'|'components'} [params.env] - Optional parameters for opening the page.
     * @param {boolean} [params.willThrow] - Optional flag to simulate an exception
     */
    async openPage({ env = 'app', willThrow = false } = {}) {
        await this.mocks.install();
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
        const searchParams = new URLSearchParams({ env, debugState: 'true', willThrow: String(willThrow) });
        await this.page.goto('/' + '?' + searchParams.toString());
    }

    /**
     * We test the fully built artifacts, so for each test run we need to
     * select the correct HTML file.
     * @return {string}
     */
    get basePath() {
        return this.build.switch({
            // windows: () => '../../build/windows/pages/release-notes',
            apple: () => '../Sources/ContentScopeScripts/dist/pages/release-notes',
        });
    }

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new ReleaseNotesPage(page, build, platformInfo);
    }

    async reducedMotion() {
        await this.page.emulateMedia({ reducedMotion: 'reduce' });
    }

    async darkMode() {
        await this.page.emulateMedia({ colorScheme: 'dark' });
    }

    /**
     * @param {UpdateMessage['status']} messageType
     * @param {Partial<UpdateMessage>} [dataOverrides]
     */
    async sendSubscriptionMessage(messageType, dataOverrides) {
        // Wait for the subscription handler to appear before trying to simulate push events.
        // This prevents a race condition where playwright is sending data before `.subscribe` was called
        await this.page.waitForFunction(() => 'onUpdate' in window && typeof window.onUpdate === 'function');

        const data = dataOverrides
            ? { ...sampleData[messageType], .../** @type {object} */ (dataOverrides) }
            : { ...sampleData[messageType] };

        await this.mocks.simulateSubscriptionMessage('onUpdate', data);
    }

    async releaseNotesLoading() {
        await this.sendSubscriptionMessage('loading');
    }

    async releaseNotesLoadingError() {
        await this.sendSubscriptionMessage('loadingError');
    }

    async releaseNotesLoadedWithoutPrivacyPro() {
        await this.sendSubscriptionMessage('loaded', { releaseNotesPrivacyPro: undefined });
    }

    async releaseNotesLoaded() {
        await this.sendSubscriptionMessage('loaded');
    }

    async releaseNotesUpdateReadyWithoutPrivacyPro() {
        await this.sendSubscriptionMessage('updateReady', { releaseNotesPrivacyPro: undefined });
    }

    async releaseNotesUpdateReady() {
        await this.sendSubscriptionMessage('updateReady');
    }

    async releaseNotesManualUpdateReady() {
        await this.sendSubscriptionMessage('updateReady', { automaticUpdate: false });
    }

    async releaseNotesCriticalUpdateReady() {
        await this.sendSubscriptionMessage('criticalUpdateReady');
    }

    async releaseNotesManualCriticalUpdateReady() {
        await this.sendSubscriptionMessage('criticalUpdateReady', { automaticUpdate: false });
    }

    async releaseNotesUpdateErrorWithoutPrivacyPro() {
        await this.sendSubscriptionMessage('updateError', { releaseNotesPrivacyPro: undefined });
    }

    async releaseNotesUpdateError() {
        await this.sendSubscriptionMessage('updateError');
    }

    async releaseNotesUpdateDownloading() {
        await this.sendSubscriptionMessage('updateDownloading');
    }

    async releaseNotesUpdatePreparing() {
        await this.sendSubscriptionMessage('updatePreparing');
    }

    async handlesFatalException() {
        const { page } = this;
        await expect(page.getByRole('heading')).toContainText('Something went wrong');
        const calls = await this.mocks.waitForCallCount({ method: 'reportPageException', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'release-notes',
                    method: 'reportPageException',
                    params: {
                        message: 'Simulated Exception',
                    },
                },
            },
        ]);
    }

    async didSendInitialHandshake() {
        const calls = await this.mocks.outgoing({ names: ['initialSetup'] });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'release-notes',
                    method: 'initialSetup',
                },
            },
        ]);
    }

    async didShowLoadingState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByText('Last checked: Yesterday')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — Checking for update')).toBeVisible();
        await expect(page.getByTestId('placeholder')).toBeVisible();

        await expect(page.getByRole('heading', { name: 'May 20 2024 New' })).not.toBeVisible();
        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).not.toBeVisible();
        await expect(page.getByRole('button', { name: 'Restart To Update' })).not.toBeVisible();
    }

    async didShowLoadingErrorState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByText('Last checked: Yesterday')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — Error loading update summary')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Reload Summary' })).toBeVisible();

        await expect(page.getByRole('heading', { name: 'May 20 2024 New' })).not.toBeVisible();
        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).not.toBeVisible();
        await expect(page.getByRole('button', { name: 'Restart To Update' })).not.toBeVisible();
    }

    async didShowUpdateDownloadingState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByText('Last checked: Today')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — Downloading update 74%')).toBeVisible();
        await expect(page.getByTestId('placeholder')).toBeVisible();

        await expect(page.getByRole('heading', { name: 'May 20 2024 New' })).not.toBeVisible();
        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).not.toBeVisible();
        await expect(page.getByRole('button', { name: 'Restart To Update' })).not.toBeVisible();
    }

    async didShowUpdatePreparingState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByText('Last checked: Today')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — Preparing update')).toBeVisible();
        await expect(page.getByTestId('placeholder')).toBeVisible();

        await expect(page.getByRole('heading', { name: 'May 20 2024 New' })).not.toBeVisible();
        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).not.toBeVisible();
        await expect(page.getByRole('button', { name: 'Restart To Update' })).not.toBeVisible();
    }

    async didShowUpToDateState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'May 20 2024', exact: true })).toBeVisible();

        await expect(page.getByText('Last checked: Today')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — DuckDuckGo is up to date')).toBeVisible();
        await expect(page.getByText('Version 1.0.1', { exact: true })).toBeVisible();

        await expect(page.getByTestId('placeholder')).not.toBeVisible();
        await expect(page.getByRole('button', { name: 'Restart To Update' })).not.toBeVisible();
    }

    /**
     * @param {object} options
     * @param {boolean} [options.critical=false]
     * @param {boolean} [options.manual=false]
     */
    async didShowUpdateReadyState({ critical = false, manual = false }) {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'June 20 2024 New', exact: true })).toBeVisible();

        await expect(page.getByText('Last checked: Today')).toBeVisible();
        if (critical) {
            await expect(page.getByText('Version 1.0.1 — Critical update needed')).toBeVisible();
        } else {
            await expect(page.getByText('Version 1.0.1 — A newer version of the browser is available')).toBeVisible();
        }

        if (manual) {
            await expect(page.getByRole('button', { name: 'Update DuckDuckGo' })).toBeVisible();
        } else {
            await expect(page.getByRole('button', { name: 'Restart To Update' })).toBeVisible();
        }

        await expect(page.getByText('Version 1.2.0', { exact: true })).toBeVisible();

        await expect(page.getByTestId('placeholder')).not.toBeVisible();
    }

    async didShowAutomaticUpdateReadyState() {
        return await this.didShowUpdateReadyState({});
    }

    async didShowManualUpdateReadyState() {
        return await this.didShowUpdateReadyState({ manual: true });
    }

    async didShowAutomaticCriticalUpdateReadyState() {
        return await this.didShowUpdateReadyState({ critical: true });
    }

    async didShowManualCriticalUpdateReadyState() {
        return await this.didShowUpdateReadyState({ critical: true, manual: true });
    }

    async didShowUpdateErrorState() {
        const { page } = this;
        await expect(page.getByRole('heading', { name: 'Release Notes' })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'June 20 2024 New', exact: true })).toBeVisible();

        await expect(page.getByText('Last checked: Today')).toBeVisible();
        await expect(page.getByText('Version 1.0.1 — Update failed')).toBeVisible();
        await expect(page.getByText('Version 1.2.0', { exact: true })).toBeVisible();

        await expect(page.getByTestId('placeholder')).not.toBeVisible();
    }

    async didShowReleaseNotesListWithoutPrivacyPro() {
        const { page } = this;

        await expect(
            page.getByText(
                'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            ),
        ).toBeVisible();
        await expect(page.getByText("Fixed an issue where Microsoft Teams links wouldn't open the Teams app.")).toBeVisible();
        await expect(
            page.getByText('Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.'),
        ).toBeVisible();

        await expect(
            page.getByText(
                'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            ),
        ).not.toBeVisible();
        await expect(page.getByText('Privacy Pro is currently available to U.S. residents only')).not.toBeVisible();

        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).not.toBeVisible();
        await expect(page.getByRole('link', { name: 'duckduckgo.com/pro' })).not.toBeVisible();
    }

    async didShowReleaseNotesList() {
        const { page } = this;

        await expect(page.getByRole('heading', { name: 'For Privacy Pro Subscribers' })).toBeVisible();
        await expect(page.getByRole('link', { name: 'duckduckgo.com/pro' })).toBeVisible();

        await expect(
            page.getByText(
                'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            ),
        ).toBeVisible();
        await expect(page.getByText("Fixed an issue where Microsoft Teams links wouldn't open the Teams app.")).toBeVisible();
        await expect(
            page.getByText('Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.'),
        ).toBeVisible();

        await expect(
            page.getByText(
                'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            ),
        ).toBeVisible();
        await expect(page.getByText('Privacy Pro is currently available to U.S. residents only')).toBeVisible();
        await expect(page.getByText('Not subscribed? Find out more at duckduckgo.com/pro')).toBeVisible();
    }

    async didRequestRestart() {
        const { page } = this;
        page.getByRole('button', { name: 'Restart To Update' }).click();
        const calls = await this.mocks.waitForCallCount({ method: 'browserRestart', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'release-notes',
                    method: 'browserRestart',
                    params: {},
                },
            },
        ]);
    }

    async didRequestRetryUpdate() {
        const { page } = this;
        page.getByRole('button', { name: 'Retry Update' }).click();
        const calls = await this.mocks.waitForCallCount({ method: 'retryUpdate', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'release-notes',
                    method: 'retryUpdate',
                    params: {},
                },
            },
        ]);
    }

    async didRequestRetryGettingReleaseNotes() {
        const { page } = this;
        page.getByRole('button', { name: 'Reload Summary' }).click();
        const calls = await this.mocks.waitForCallCount({ method: 'retryFetchReleaseNotes', count: 1 });
        expect(calls).toMatchObject([
            {
                payload: {
                    context: 'specialPages',
                    featureName: 'release-notes',
                    method: 'retryFetchReleaseNotes',
                    params: {},
                },
            },
        ]);
    }
}
