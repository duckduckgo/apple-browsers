import { Mocks } from '../../../shared/mocks.js';
import { perPlatform } from 'injected/integration-test/type-helpers.mjs';
import { expect, test } from '@playwright/test';

/**
 * @typedef {import('injected/integration-test/type-helpers.mjs').Build} Build
 * @typedef {import('injected/integration-test/type-helpers.mjs').PlatformInfo} PlatformInfo
 */

export class NewtabPage {
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
            featureName: 'newTabPage',
            env: 'development',
        });
        this.page.on('console', console.log);
        if (this.platform.name === 'extension') throw new Error('unreachable - not supported in extension platform');
        this.mocks.defaultResponses({
            requestSetAsDefault: {},
            requestImport: {},
            /** @type {import('../types/new-tab.ts').InitialSetupResponse} */
            initialSetup: {
                widgets: [{ id: 'rmf' }, { id: 'nextSteps' }, { id: 'favorites' }, { id: 'privacyStats' }],
                widgetConfigs: [
                    { id: 'nextSteps', visibility: 'visible' },
                    { id: 'favorites', visibility: 'visible' },
                    { id: 'privacyStats', visibility: 'visible' },
                ],
                env: 'development',
                locale: 'en',
                platform: {
                    name: this.platform.name || 'windows',
                },
                updateNotification: { content: null },
                customizer: { theme: 'system', userImages: [], userColor: null, background: { kind: 'default' } },
            },
            stats_getConfig: {},
            stats_getData: {},
            nextSteps_getConfig: {},
            nextSteps_getData: {},
            rmf_getData: {},
            widgets_setConfig: {},
            omnibar_getConfig: { mode: 'search', enableAi: false },
            omnibar_getSuggestions: { suggestions: { topHits: [], duckduckgoSuggestions: [], localSuggestions: [] } },
            omnibar_setConfig: {},
            omnibar_openSuggestion: {},
            omnibar_submitSearch: {},
            omnibar_submitChat: {},
        });
    }

    /**
     * Opens a page with optional parameters.
     * This method ensures that mocks are installed and routes are set up before navigating to the page.
     * @param {Object} [params] - Optional parameters for opening the page.
     * @param {'debug' | 'production'} [params.mode] - Optional parameters for opening the page.
     * @param {boolean} [params.willThrow] - Optional flag to simulate an exception
     * @param {string|number} [params.favorites] - Optional flag to preload a list of favorites
     * @param {string|string[]} [params.nextSteps] - Optional flag to load Next Steps cards
     * @param {Record<string, any>} [params.additional] - Optional map of key/values to add
     * @param {string} [params.rmf] - Optional flag to add certain rmf example
     * @param {string} [params.updateNotification] - Optional flag to point to display=components view with certain rmf example visible
     * @param {string} [params.pir] - Optional flag to add certain Freemium PIR Banner example
     * @param {string} [params.platformName] - Optional parameters for opening the page.
     */
    async openPage({
        mode = 'debug',
        additional,
        platformName,
        willThrow = false,
        favorites,
        nextSteps,
        rmf,
        pir,
        updateNotification,
    } = {}) {
        await this.mocks.install();
        const searchParams = new URLSearchParams({ mode, willThrow: String(willThrow) });

        if (favorites !== undefined) {
            searchParams.set('favorites', String(favorites));
        }

        if (rmf !== undefined) {
            searchParams.set('rmf', rmf);
        }

        if (nextSteps !== undefined) {
            if (typeof nextSteps === 'string') {
                searchParams.set('next-steps', nextSteps);
            } else if (Array.isArray(nextSteps)) {
                for (const step of nextSteps) {
                    searchParams.append('next-steps', step);
                }
            }
        }

        if (pir !== undefined) {
            searchParams.set('pir', pir);
        }

        if (platformName !== undefined) {
            searchParams.set('platform', platformName);
        }

        if (updateNotification !== undefined) {
            searchParams.set('update-notification', updateNotification);
        }

        for (const [key, value] of Object.entries(additional || {})) {
            searchParams.set(key, value);
        }

        // eslint-disable-next-line no-undef
        if (process.env.PAGE) {
            await this.page.goto('/' + '?' + searchParams.toString());
        } else {
            test.info().annotations.push({
                type: 'params',
                description: '' + searchParams.toString(),
            });
            await this.page.goto('/new-tab' + '?' + searchParams.toString());
        }
    }

    /**
     * We test the fully built artifacts, so for each test run we need to
     * select the correct HTML file.
     * @return {string}
     */
    get basePath() {
        return this.build.switch({
            windows: () => '../build/windows/pages/new-tab',
            integration: () => '../build/integration/pages/new-tab',
        });
    }

    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("@playwright/test").TestInfo} testInfo
     */
    static create(page, testInfo) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(testInfo.project.use);
        return new NewtabPage(page, build, platformInfo);
    }

    async reducedMotion() {
        await this.page.emulateMedia({ reducedMotion: 'reduce' });
    }

    async darkMode() {
        await this.page.emulateMedia({ colorScheme: 'dark' });
    }

    async waitForCustomizer() {
        await this.page.getByRole('button', { name: 'Customize' }).waitFor();
    }

    /**
     * @param {object} params
     * @param {string} params.hex
     * @returns {Promise<void>}
     */
    async hasBackgroundColor({ hex }) {
        const r = parseInt(hex.slice(1, 3), 16);
        const g = parseInt(hex.slice(3, 5), 16);
        const b = parseInt(hex.slice(5, 7), 16);
        const rgb = `rgb(${[r, g, b].join(', ')})`;
        await expect(this.page.locator('body')).toHaveCSS('background-color', rgb, { timeout: 1000 });
    }
}
