import { test, expect } from '@playwright/test';
import { OVERLAY_ID } from '../src/features/autofill-password-import';
import { ResultsCollector } from './page-objects/results-collector.js';

const HTML = '/autofill-password-import/index.html';
const CONFIG = './integration-test/test-pages/autofill-password-import/config/config.json';

test('Password import feature', async ({ page }, testInfo) => {
    const collector = ResultsCollector.create(page, testInfo.project.use);
    await collector.load(HTML, CONFIG);

    const passwordImportFeature = new AutofillPasswordImportSpec(page);
    await passwordImportFeature.clickOnElement('Home page');
    await passwordImportFeature.waitForAnimation();

    await passwordImportFeature.clickOnElement('Signin page');
    await passwordImportFeature.waitForAnimation();

    await passwordImportFeature.clickOnElement('Export page');
    await passwordImportFeature.waitForAnimation();

    // Test unsupported path
    await passwordImportFeature.clickOnElement('Unsupported page');
    const overlay = page.locator(`#${OVERLAY_ID}`);
    await expect(overlay).not.toBeVisible();
});

class AutofillPasswordImportSpec {
    /**
     * @param {import("@playwright/test").Page} page
     */
    constructor(page) {
        this.page = page;
    }

    /**
     * Helper to assert that an element is animating
     */
    async waitForAnimation() {
        const locator = this.page.locator(`#${OVERLAY_ID}`);
        await expect(locator).toBeVisible();
    }

    /**
     * Helper to click on a button accessed via the aria-label attrbitue
     * @param {string} text
     */
    async clickOnElement(text) {
        const element = this.page.getByText(text);
        await element.click();
    }
}
