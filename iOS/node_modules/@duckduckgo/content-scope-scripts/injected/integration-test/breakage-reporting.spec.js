import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';

const HTML = '/breakage-reporting/index.html';
const CONFIG = './integration-test/test-pages/breakage-reporting/config/config.json';
test('Breakage Reporting Feature', async ({ page }, testInfo) => {
    const collector = ResultsCollector.create(page, testInfo.project.use);
    await collector.load(HTML, CONFIG);

    const breakageFeature = new BreakageReportingSpec(page);
    await breakageFeature.navigate();

    await collector.simulateSubscriptionMessage('breakageReporting', 'getBreakageReportValues', {});
    await collector.waitForMessage('breakageReportResult');
    const calls = await collector.outgoingMessages();

    expect(calls.length).toBe(1);
    const result = /** @type {import("@duckduckgo/messaging").NotificationMessage} */ (calls[0].payload);
    expect(result.params?.jsPerformance.length).toBe(1);
    expect(result.params?.jsPerformance[0]).toBeGreaterThan(0);
    expect(result.params?.referrer).toBe('http://localhost:3220/breakage-reporting/index.html');
});

export class BreakageReportingSpec {
    /**
     * @param {import("@playwright/test").Page} page
     */
    constructor(page) {
        this.page = page;
    }

    async navigate() {
        await this.page.evaluate(() => {
            window.location.href = '/breakage-reporting/pages/ref.html';
        });
        await this.page.waitForURL('**/ref.html');

        // Wait for first paint event to ensure we can get the performance metrics
        await this.page.evaluate(() => {
            const response = new Promise((resolve) => {
                const observer = new PerformanceObserver((list) => {
                    list.getEntries().forEach((entry) => {
                        if (entry.name === 'first-paint') {
                            observer.disconnect();
                            // @ts-expect-error - error TS2810: Expected 1 argument, but got 0. 'new Promise()' needs a JSDoc hint to produce a 'resolve' that can be called without arguments.
                            resolve();
                        }
                    });
                });

                observer.observe({ type: 'paint', buffered: true });
            });
            return response;
        });
    }
}
