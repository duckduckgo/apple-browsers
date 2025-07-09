import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';

const HTML = '/webcompat/pages/message-handlers.html';
const CONFIG = './integration-test/test-pages/webcompat/config/message-handlers.json';
test('web compat message handlers', async ({ page }, testInfo) => {
    const webcompat = ResultsCollector.create(page, testInfo.project.use);
    await webcompat.load(HTML, CONFIG);
    const results = await webcompat.results();
    expect(results).toMatchObject({
        'webkit.messageHandlers - polyfill prevents throw': [
            {
                name: 'Error not thrown polyfil',
                result: true,
                expected: true,
            },
        ],
        'webkit.messageHandlers - undefined should throw': [
            {
                name: 'undefined handler should throw',
                result: true,
                expected: true,
            },
        ],
        'webkit.messageHandlers - reflected message': [
            {
                name: 'reflected message should pass through',
                result: 'test',
                expected: 'test',
            },
        ],
    });
});
