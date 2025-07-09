import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';

const HAR_FILE = 'integration-test/data/har/example.com/example.com.har';
const CONFIG = {
    features: {
        navigatorInterface: {
            state: 'enabled',
            exceptions: [],
        },
    },
    unprotectedTemporary: [],
};

test.describe('insecure contexts', () => {
    test('should expose navigator.isDuckDuckGo in insecure contexts', async ({ page }, testInfo) => {
        const example = ResultsCollector.create(page, testInfo.project.use);
        await example.setup({ config: CONFIG, locale: 'en' });
        await page.routeFromHAR(HAR_FILE);
        await page.goto('http://example.com');

        // verify the platform was set
        const actual = await page.evaluate('navigator.duckduckgo.platform');
        const expected = /** @type {any} */ (testInfo.project.use).platform;
        expect(actual).toEqual(expected);
    });
});
