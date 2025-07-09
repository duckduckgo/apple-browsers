import { test, expect } from '@playwright/test';
import { ResultsCollector } from './page-objects/results-collector.js';
import { readOutgoingMessages } from '@duckduckgo/messaging/lib/test-utils.mjs';

const ENABLED_CONFIG = 'integration-test/test-pages/message-bridge/config/message-bridge-enabled.json';
const DISABLED_CONFIG = 'integration-test/test-pages/message-bridge/config/message-bridge-disabled.json';
const ENABLED_HTML = '/message-bridge/pages/enabled.html';
const DISABLED_HTML = '/message-bridge/pages/disabled.html';

/**
 * This feature needs 2 sets of scripts in the page. For example,
 * apple + apple-isolated
 *
 * @param {import("playwright-core").Page} page
 * @param {import("@playwright/test").TestInfo} testInfo
 */
function setupBothContexts(page, testInfo) {
    const pageWorld = ResultsCollector.create(page, testInfo.project.use);
    const isolated = ResultsCollector.create(page, {
        injectName: pageWorld.isolatedVariant(),
        platform: pageWorld.platform.name,
    });

    // add user preferences to both
    isolated.withUserPreferences({ messageSecret: 'ABC' });
    pageWorld.withUserPreferences({ messageSecret: 'ABC' });

    return { pageWorld, isolated };
}

test('message bridge when enabled (apple)', async ({ page }, testInfo) => {
    // page.on('console', (msg) => console.log(msg.text()));
    const { pageWorld, isolated } = setupBothContexts(page, testInfo);

    // seed the request->re
    isolated.withMockResponse({
        sampleData: /** @type {any} */ ({
            ghi: 'jkl',
        }),
    });

    // inject the scripts into the isolated world (with a different messaging context)
    await isolated.setup({ config: ENABLED_CONFIG });

    // now load the page
    await pageWorld.load(ENABLED_HTML, ENABLED_CONFIG);

    // simulate a push event
    await isolated.simulateSubscriptionMessage('exampleFeature', 'onUpdate', { abc: 'def' });

    // get all results
    const results = await pageWorld.results();
    expect(results['Creating the bridge']).toStrictEqual([
        { name: 'bridge.notify', result: 'function', expected: 'function' },
        { name: 'bridge.request', result: 'function', expected: 'function' },
        { name: 'bridge.subscribe', result: 'function', expected: 'function' },
        { name: 'data', result: [{ abc: 'def' }, { ghi: 'jkl' }], expected: [{ abc: 'def' }, { ghi: 'jkl' }] },
    ]);

    // verify messaging calls
    const calls = await page.evaluate(readOutgoingMessages);
    expect(calls.length).toBe(2);
    const pixel = calls[0].payload;
    const request = calls[1].payload;

    expect(pixel).toStrictEqual({
        context: 'contentScopeScriptsIsolated',
        featureName: 'exampleFeature',
        method: 'pixel',
        params: {},
    });

    const { id, ...rest } = /** @type {import("@duckduckgo/messaging").RequestMessage} */ (request);

    expect(rest).toStrictEqual({
        context: 'contentScopeScriptsIsolated',
        featureName: 'exampleFeature',
        method: 'sampleData',
        params: {},
    });

    if (!('id' in request)) throw new Error('unreachable');

    expect(typeof request.id).toBe('string');
    expect(request.id.length).toBeGreaterThan(10);
});

test('message bridge when disabled (apple)', async ({ page }, testInfo) => {
    // page.on('console', (msg) => console.log(msg.text()));
    const { pageWorld, isolated } = setupBothContexts(page, testInfo);

    // inject the scripts into the isolated world (with a different messaging context)
    await isolated.setup({ config: DISABLED_CONFIG });

    // now load the main page
    await pageWorld.load(DISABLED_HTML, DISABLED_CONFIG);

    // verify no outgoing calls were made
    const calls = await page.evaluate(readOutgoingMessages);
    expect(calls).toHaveLength(0);

    // get all results
    const results = await pageWorld.results();
    expect(results['Creating the bridge, but it is unavailable']).toStrictEqual([
        { name: 'error', result: 'Did not install Message Bridge', expected: 'Did not install Message Bridge' },
    ]);
});
