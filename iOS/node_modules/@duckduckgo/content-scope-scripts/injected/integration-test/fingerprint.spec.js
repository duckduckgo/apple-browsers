/**
 *  Tests for fingerprint defenses. Ensure that fingerprinting is actually being blocked.
 */
import { test as base, expect } from '@playwright/test';
import { testContextForExtension, gotoAndWait } from './helpers/harness.js';
import { createRequire } from 'node:module';

// eslint-disable-next-line no-redeclare
const require = createRequire(import.meta.url);

const test = testContextForExtension(base);

const expectedFingerprintValues = {
    availTop: 0,
    availLeft: 0,
    wAvailTop: 0,
    wAvailLeft: 0,
    colorDepth: 24,
    pixelDepth: 24,
    productSub: '20030107',
    vendorSub: '',
};

const pagePath = '/index.html';
const tests = [{ url: `http://localhost:3220${pagePath}` }, { url: `http://127.0.0.1:8383${pagePath}` }];
const enabledCanvasArgs = {
    site: {
        enabledFeatures: ['fingerprintingCanvas'],
    },
    featureSettings: {
        fingerprintingCanvas: {
            additionalEnabledCheck: 'enabled',
        },
    },
};

test.describe.serial('All Fingerprint Defense Tests (must run in serial)', () => {
    test.describe.serial('Fingerprint Defense Tests', () => {
        for (const _test of tests) {
            test(`${_test.url} should include anti-fingerprinting code`, async ({ page, altServerPort }) => {
                console.log('running:', altServerPort);
                await gotoAndWait(page, _test.url, enabledCanvasArgs);
                const values = await page.evaluate(() => {
                    return {
                        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                        availTop: screen.availTop,
                        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                        availLeft: screen.availLeft,
                        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                        wAvailTop: window.screen.availTop,
                        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                        wAvailLeft: window.screen.availLeft,
                        colorDepth: screen.colorDepth,
                        pixelDepth: screen.pixelDepth,
                        productSub: navigator.productSub,
                        vendorSub: navigator.vendorSub,
                    };
                });

                for (const [name, prop] of Object.entries(values)) {
                    await test.step(name, () => {
                        expect(prop).toEqual(expectedFingerprintValues[name]);
                    });
                }

                await page.close();
            });
        }
    });

    test.describe.serial('First Party Fingerprint Randomization', () => {
        /**
         * @param {import("@playwright/test").Page} page
         * @param {tests[number]} test
         */
        async function runTest(page, test) {
            await gotoAndWait(page, test.url, enabledCanvasArgs);
            const lib = require.resolve('@fingerprintjs/fingerprintjs/dist/fp.js');
            await page.addScriptTag({ path: lib });

            const fingerprint = await page.evaluate(() => {
                /* global FingerprintJS */
                return (async () => {
                    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                    const fp = await FingerprintJS.load();
                    return fp.get();
                })();
            });

            return {
                canvas: fingerprint.components.canvas.value,
                plugin: fingerprint.components.plugins.value,
            };
        }

        for (const testCase of tests) {
            test(`Fingerprints should not change amongst page loads test ${testCase.url}`, async ({ page, altServerPort }) => {
                console.log('running:', altServerPort);
                const result = await runTest(page, testCase);

                const result2 = await runTest(page, testCase);
                expect(result.canvas).toEqual(result2.canvas);
                expect(result.plugin).toEqual(result2.plugin);
            });
        }

        test('Fingerprints should not match across first parties', async ({ page, altServerPort }) => {
            console.log('running:', altServerPort);
            const canvas = new Set();
            const plugin = new Set();

            for (const testCase of tests) {
                const result = await runTest(page, testCase);

                // Add the fingerprints to a set, if the result doesn't match it won't be added
                canvas.add(JSON.stringify(result.canvas));
                plugin.add(JSON.stringify(result.plugin));
            }

            // Ensure that the number of test pages match the number in the set
            expect(canvas.size).toEqual(tests.length);
            expect(plugin.size).toEqual(1);
        });
    });

    test.describe.serial('Verify injected script is not visible to the page', () => {
        tests.forEach((testCase) => {
            test(`Fingerprints should not match across first parties ${testCase.url}`, async ({ page, altServerPort }) => {
                console.log('running:', altServerPort);
                await gotoAndWait(page, testCase.url, enabledCanvasArgs);

                // give it another second just to be sure
                await page.waitForTimeout(1000);

                const sjclVal = await page.evaluate(() => {
                    if ('sjcl' in window) {
                        return 'visible';
                    } else {
                        return 'invisible';
                    }
                });

                expect(sjclVal).toEqual('invisible');
            });
        });
    });
});
