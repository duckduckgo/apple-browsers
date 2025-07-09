import { expect } from '@playwright/test';
import { readFileSync } from 'fs';
import { perPlatform } from '../type-helpers.mjs';
import { ResultsCollector } from './results-collector.js';
import { createCaptchaResponse } from '../mocks/broker-protection/captcha.js';
import { createFeatureConfig } from '../mocks/broker-protection/feature-config.js';

export class BrokerProtectionPage {
    /**
     * @param {import("@playwright/test").Page} page
     * @param {import("../type-helpers.mjs").Build} build
     * @param {import("@duckduckgo/messaging/lib/test-utils.mjs").PlatformInfo} platform
     */
    constructor(page, build, platform) {
        this.page = page;
        this.collector = new ResultsCollector(page, build, platform);
    }

    async enabled() {
        await this.collector.setup({ config: createFeatureConfig({ state: 'enabled' }) });
    }

    /**
     * @param {object} config
     */
    async withFeatureConfig(config) {
        await this.collector.setup({ config });
    }

    /**
     * @param {string} page - add more pages here as you need them
     * @return {Promise<void>}
     */
    async navigatesTo(page) {
        await this.page.goto('/broker-protection/pages/' + page);
    }

    /**
     * @param {string} selector
     */
    async elementIsAbsent(selector) {
        // control - ensure the element isn't there first
        const e = await this.page.$(selector);
        expect(e).toBeNull();
    }

    /**
     * @return {Promise<void>}
     */
    async isFormFilled() {
        await expect(this.page.getByLabel('First Name:', { exact: true })).toHaveValue('John');
        await expect(this.page.getByLabel('Last Name:', { exact: true })).toHaveValue('Smith');
        await expect(this.page.getByLabel('Phone Number:', { exact: true })).toHaveValue(/^\d{10}$/);
        await expect(this.page.getByLabel('Street Address:', { exact: true })).toHaveValue(/^\d+ [A-Za-z]+(?: [A-Za-z]+)?$/);
        await expect(this.page.locator('#state')).toHaveValue('IL');
        await expect(this.page.getByLabel('Zip Code:', { exact: true })).toHaveValue(/^\d{5}$/);

        const randomValue = await this.page.getByLabel('Random number between 5 and 15:').inputValue();
        const randomValueInt = parseInt(randomValue);

        expect(Number.isInteger(randomValueInt)).toBe(true);
        expect(randomValueInt).toBeGreaterThanOrEqual(5);
        expect(randomValueInt).toBeLessThanOrEqual(15);

        await expect(this.page.getByLabel('City & State:', { exact: true })).toHaveValue('Chicago, IL');
    }

    /**
     * @param {string} responseElementSelector
     * @return {Promise<void>}
     */
    async isCaptchaTokenFilled(responseElementSelector) {
        const captchaTarget = await this.page.$(responseElementSelector);
        const captchaToken = await captchaTarget?.evaluate((element) => ('value' in element ? element.value : element.innerHTML));
        expect(captchaToken).toBe('test_token');
    }

    /**
     * @return {void}
     */
    isExtractMatch(response, person) {
        expect(person).toMatchObject(response);
    }

    /**
     * @return {void}
     */
    isUrlMatch(response) {
        expect(response.url).toBe('https://www.verecor.com/profile/search?fname=Ben&lname=Smith&state=fl&city=New-York&fage=41-50');
    }

    /**
     * @param {object} response
     * @param {object} captchaParams
     * @param {string} captchaParams.captchaType
     * @param {string} captchaParams.targetPage
     * @param {string} [captchaParams.siteKey]
     *
     * @return {void}
     */
    isCaptchaMatch(response, { captchaType, targetPage, ...overrides }) {
        const expectedResponse = createCaptchaResponse({ captchaType, targetPage, ...overrides });

        switch (captchaType) {
            case 'image':
                // Validate that the correct keys are present in the response
                expect(Object.keys(response).sort()).toStrictEqual(Object.keys(expectedResponse).sort());
                // Validate that the siteKey looks like a base64 encoded image
                expect(response.siteKey).toMatch(/^data:image\/jpeg;base64,/);
                break;
            default:
                expect(response).toStrictEqual(expectedResponse);
        }
    }

    async isCaptchaError() {
        expect(await this.getErrorMessage()).not.toBeFalsy();
    }

    /**
     * @return {void}
     */
    isQueryParamRemoved(response) {
        const url = new URL(response.url);
        expect(url.searchParams.toString()).toBe('');
    }

    /**
     * @param meta
     */
    responseContainsMetadata(meta) {
        expect(meta.extractResults).toHaveLength(10);
        expect(meta.extractResults.filter((x) => x.result === true)).toHaveLength(1);
        expect(meta.extractResults.filter((x) => x.result === false)).toHaveLength(9);
        const match = meta.extractResults.find((x) => x.result === true);
        expect(match.matchedFields).toMatchObject(['name', 'age', 'addressCityStateList']);
        expect(match.element).toBe(undefined);
        expect(match.score).toBe(3);
    }

    /**
     * Simulate the native-side pushing an action into the client-side JS
     *
     * @param {string} action
     * @return {Promise<void>}
     */
    async receivesAction(action) {
        const actionJson = JSON.parse(readFileSync('./integration-test/test-pages/broker-protection/actions/' + action, 'utf8'));
        await this.simulateSubscriptionMessage('onActionReceived', actionJson);
    }

    /**
     * @param {{state: {action: Record<string, any>}}} action
     * @return {Promise<void>}
     */
    async receivesInlineAction(action) {
        await this.simulateSubscriptionMessage('onActionReceived', action);
    }

    /**
     * @param {string} name
     * @param {Record<string, any>} payload
     */
    async simulateSubscriptionMessage(name, payload) {
        await this.collector.simulateSubscriptionMessage('brokerProtection', name, payload);
    }

    async getActionCompletedParams() {
        return await this.collector.waitForMessage('actionCompleted');
    }

    async getSuccessResponse() {
        const response = await this.getActionCompletedParams();
        this.isSuccessMessage(response);
        return this._getResultFromResponse(response).success.response;
    }

    async getErrorMessage() {
        const response = await this.getActionCompletedParams();
        this.isErrorMessage(response);
        return this._getResultFromResponse(response).error.message;
    }

    /**
     * @param {object} response
     */
    isErrorMessage(response) {
        expect('error' in this._getResultFromResponse(response)).toBe(true);
    }

    isSuccessMessage(response) {
        expect('success' in this._getResultFromResponse(response)).toBe(true);
    }

    /**
     * @param {object} response
     */
    _getResultFromResponse(response) {
        return response[0].payload?.params?.result;
    }

    /**
     * Helper for creating an instance per platform
     * @param {import("@playwright/test").Page} page
     * @param {Record<string, any>} use
     */
    static create(page, use) {
        // Read the configuration object to determine which platform we're testing against
        const { platformInfo, build } = perPlatform(use);
        return new BrokerProtectionPage(page, build, platformInfo);
    }
}
