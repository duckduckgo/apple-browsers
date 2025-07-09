import { test, expect } from '@playwright/test';
import path from 'path';
import { readFileSync } from 'fs';
import { baseFeatures } from '../src/features.js';

const testRoot = path.join('integration-test');

function getHARPath(harFile) {
    return path.join(testRoot, 'data', 'har', harFile);
}

const css = readFileSync('../build/integration/contentScope.js', 'utf8');
const parsedConfig = {};
// Construct a parsed config object with all base features enabled
Object.keys(baseFeatures).forEach((key) => {
    parsedConfig[key] = {
        enabled: 'enabled',
    };
});

function wrapScript(js, replacements) {
    for (const [find, replace] of Object.entries(replacements)) {
        js = js.replace(find, JSON.stringify(replace));
    }
    return js;
}

const tests = [
    // Generated using `node scripts/generate-har.js`
    { url: 'duckduckgo.com/c-s-s-says-hello', har: getHARPath('duckduckgo.com/search.har') },
];

test.describe('Remotely loaded files tests', () => {
    tests.forEach((testCase) => {
        test(`${testCase.url} should load resources and look correct`, async ({ page }, testInfo) => {
            const injectedJS = wrapScript(css, {
                $CONTENT_SCOPE$: parsedConfig,
                $USER_UNPROTECTED_DOMAINS$: [],
                $USER_PREFERENCES$: {
                    // @ts-expect-error - no platform key
                    platform: { name: testInfo.project.use.platform },
                    debug: true,
                },
            });
            await page.addInitScript({ content: injectedJS });
            await page.routeFromHAR(testCase.har);
            await page.goto(`https://${testCase.url}`, { waitUntil: 'networkidle' });
            const values = await page.evaluate(() => {
                return {
                    results: document.querySelectorAll('[data-layout="organic"]').length,
                };
            });
            expect(values.results).toBeGreaterThan(1);
        });
    });
});
