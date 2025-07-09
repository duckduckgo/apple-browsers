import { gotoAndWait } from './helpers/harness.js';
import { test, expect } from '@playwright/test';

test.describe('Web Share API', () => {
    function checkForCanShare() {
        return 'canShare' in navigator;
    }
    function checkForShare() {
        return 'share' in navigator;
    }

    test.describe('disabled feature', () => {
        test('should not expose navigator.canShare() and navigator.share()', async ({ page }) => {
            await gotoAndWait(page, '/blank.html', { site: { enabledFeatures: [] } }, null, 'script');
            const noCanShare = await page.evaluate(checkForCanShare);
            const noShare = await page.evaluate(checkForShare);
            // Base implementation of the test env should not have it (it's only available on mobile)
            expect(noCanShare).toEqual(false);
            expect(noShare).toEqual(false);
        });
    });

    test.describe('disabled sub-feature', () => {
        test('should not expose navigator.canShare() and navigator.share()', async ({ page }) => {
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: {
                        enabledFeatures: ['webCompat'],
                    },
                    featureSettings: {
                        webCompat: {
                            // no webShare
                        },
                    },
                },
                null,
                'script',
            );
            const noCanShare = await page.evaluate(checkForCanShare);
            const noShare = await page.evaluate(checkForShare);
            // Base implementation of the test env should not have it (it's only available on mobile)
            expect(noCanShare).toEqual(false);
            expect(noShare).toEqual(false);
        });
    });

    test.describe('enabled feature', () => {
        async function navigate(page) {
            page.on('console', console.log);
            await gotoAndWait(
                page,
                '/blank.html',
                {
                    site: {
                        enabledFeatures: ['webCompat'],
                    },
                    featureSettings: {
                        webCompat: {
                            webShare: 'enabled',
                        },
                    },
                },
                null,
                'script',
            );
        }

        test('should expose navigator.canShare() and navigator.share() when enabled', async ({ page }) => {
            await navigate(page);
            const hasCanShare = await page.evaluate(checkForCanShare);
            const hasShare = await page.evaluate(checkForShare);
            expect(hasCanShare).toEqual(true);
            expect(hasShare).toEqual(true);
        });

        test.describe('navigator.canShare()', () => {
            test('should not let you share files', async ({ page }) => {
                await navigate(page);
                const refuseFileShare = await page.evaluate(() => {
                    return navigator.canShare({ text: 'xxx', files: [] });
                });
                expect(refuseFileShare).toEqual(false);
            });

            test('should not let you share non-http urls', async ({ page }) => {
                await navigate(page);
                const refuseShare = await page.evaluate(() => {
                    return navigator.canShare({ url: 'chrome://bla' });
                });
                expect(refuseShare).toEqual(false);
            });

            test('should allow relative links', async ({ page }) => {
                await navigate(page);
                const allowShare = await page.evaluate(() => {
                    return navigator.canShare({ url: 'bla' });
                });
                expect(allowShare).toEqual(true);
            });

            test('should support only the specific fields', async ({ page }) => {
                await navigate(page);
                const refuseShare = await page.evaluate(() => {
                    // eslint-disable-next-line
                    // @ts-ignore intentionally malformed data
                    return navigator.canShare({ foo: 'bar' });
                });
                expect(refuseShare).toEqual(false);
            });

            test('should let you share stuff', async ({ page }) => {
                await navigate(page);
                let canShare = await page.evaluate(() => {
                    return navigator.canShare({ url: 'http://example.com' });
                });
                expect(canShare).toEqual(true);

                canShare = await page.evaluate(() => {
                    return navigator.canShare({ text: 'the grass was greener' });
                });
                expect(canShare).toEqual(true);

                canShare = await page.evaluate(() => {
                    return navigator.canShare({ title: 'the light was brighter' });
                });
                expect(canShare).toEqual(true);

                canShare = await page.evaluate(() => {
                    return navigator.canShare({ text: 'with friends surrounded', title: 'the nights of wonder' });
                });
                expect(canShare).toEqual(true);
            });
        });

        test.describe('navigator.share()', () => {
            async function beforeEach(page) {
                await page.evaluate(() => {
                    globalThis.shareReq = null;
                    globalThis.cssMessaging.impl.request = (req) => {
                        globalThis.shareReq = req;
                        return Promise.resolve({});
                    };
                });
            }
            test.describe('(no errors from Android)', () => {
                /**
                 * @param {import("@playwright/test").Page} page
                 * @param {any} data
                 * @return {Promise<any>}
                 */
                async function checkShare(page, data) {
                    const payload = `navigator.share(${JSON.stringify(data)})`;
                    const result = await page.evaluate(payload).catch((e) => {
                        return { threw: e };
                    });
                    const message = await page.evaluate(() => {
                        console.log('did read?');
                        return globalThis.shareReq;
                    });
                    return { result, message };
                }

                test('should let you share text', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { text: 'xxx' });
                    expect(message).toMatchObject({ featureName: 'webCompat', method: 'webShare', params: { text: 'xxx' } });
                    expect(result).toBeUndefined();
                });

                test('should let you share url', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { url: 'http://example.com' });
                    expect(message).toMatchObject({ featureName: 'webCompat', method: 'webShare', params: { url: 'http://example.com/' } });
                    expect(result).toBeUndefined();
                });

                test('should let you share title alone', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { title: 'xxx' });
                    expect(message).toMatchObject({ featureName: 'webCompat', method: 'webShare', params: { title: 'xxx', text: '' } });
                    expect(result).toBeUndefined();
                });

                test('should let you share title and text', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { title: 'xxx', text: 'yyy' });
                    expect(message).toMatchObject({ featureName: 'webCompat', method: 'webShare', params: { title: 'xxx', text: 'yyy' } });
                    expect(result).toBeUndefined();
                });

                test('should let you share title and url', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { title: 'xxx', url: 'http://example.com' });
                    expect(message).toMatchObject({
                        featureName: 'webCompat',
                        method: 'webShare',
                        params: { title: 'xxx', url: 'http://example.com/' },
                    });
                    expect(result).toBeUndefined();
                });

                test('should combine text and url when both are present', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { text: 'xxx', url: 'http://example.com' });
                    expect(message).toMatchObject({
                        featureName: 'webCompat',
                        method: 'webShare',
                        params: { text: 'xxx http://example.com/' },
                    });
                    expect(result).toBeUndefined();
                });

                test('should throw when sharing files', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { title: 'title', files: [] });
                    expect(message).toBeNull();
                    expect(result.threw.message).toContain('TypeError: Invalid share data');
                });

                test('should throw when sharing non-http urls', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { url: 'chrome://bla' });
                    expect(message).toBeNull();
                    expect(result.threw.message).toContain('TypeError: Invalid share data');
                });

                test('should handle relative urls', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { url: 'bla' });
                    expect(message.params.url).toMatch(/^http:\/\/localhost:\d+\/bla$/);
                    expect(result).toBeUndefined();
                });

                test('should treat empty url as relative', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    const { result, message } = await checkShare(page, { url: '' });
                    expect(message.params.url).toMatch(/^http:\/\/localhost:\d+\//);
                    expect(result).toBeUndefined();
                });
            });

            test.describe('(handling errors from Android)', () => {
                test('should handle messaging error', async ({ page }) => {
                    // page.on('console', (msg) => console.log(msg.type(), msg.text()))
                    await navigate(page);
                    await beforeEach(page);

                    await page.evaluate(() => {
                        globalThis.cssMessaging.impl.request = () => {
                            return Promise.reject(new Error('something wrong'));
                        };
                    });
                    const result = await page.evaluate('navigator.share({ text: "xxx" })').catch((e) => {
                        return { threw: e };
                    });

                    // In page context, it should be a DOMException with name DataError, but page.evaluate() serializes everything in the message
                    expect(result.threw.message).toContain('DataError: something wrong');
                });

                test('should handle soft failures', async ({ page }) => {
                    await navigate(page);
                    await beforeEach(page);
                    await page.evaluate(() => {
                        globalThis.cssMessaging.impl.request = () => {
                            return Promise.resolve({ failure: { name: 'AbortError', message: 'some error message' } });
                        };
                    });
                    const result = await page.evaluate('navigator.share({ text: "xxx" })').catch((e) => {
                        return { threw: e };
                    });

                    // In page context, it should be a DOMException with name AbortError, but page.evaluate() serializes everything in the message
                    expect(result.threw.message).toContain('AbortError: some error message');
                });
            });
        });
    });
});
