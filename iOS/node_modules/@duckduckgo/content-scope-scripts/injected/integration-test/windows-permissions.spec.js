import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';

const HTML = '/permissions/index.html';
const CONFIG = './integration-test/test-pages/permissions/config/permissions.json';

test('Windows Permissions Usage', async ({ page }, testInfo) => {
    const perms = ResultsCollector.create(page, testInfo.project.use);
    await perms.load(HTML, CONFIG);
    const results = await perms.results();
    const match = results['Disabled Windows Permissions'];

    for (const result of match) {
        expect(result.result).toEqual(result.expected);
    }
});
