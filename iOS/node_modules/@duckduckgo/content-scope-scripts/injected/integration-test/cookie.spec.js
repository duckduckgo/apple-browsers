import { test as base, expect } from '@playwright/test';
import { gotoAndWait, testContextForExtension } from './helpers/harness.js';

const test = testContextForExtension(base);

test.describe('Cookie protection tests', () => {
    test('should restrict the expiry of first-party cookies', async ({ page }) => {
        await gotoAndWait(page, '/index.html');
        const result = await page.evaluate(async () => {
            document.cookie = 'test=1; expires=Wed, 21 Aug 2040 20:00:00 UTC;';
            // wait for a tick, as cookie modification happens in a promise
            await new Promise((resolve) => setTimeout(resolve, 1));
            // @ts-expect-error - cookieStore API types are missing here
            // eslint-disable-next-line no-undef
            return cookieStore.get('test');
        });
        expect(result.name).toEqual('test');
        expect(result.value).toEqual('1');
        expect(result.expires).toBeLessThan(Date.now() + 605_000_000);
    });

    test('non-string cookie values do not bypass protection', async ({ page }) => {
        await gotoAndWait(page, '/index.html');

        const result = await page.evaluate(async () => {
            // @ts-expect-error - Invalid argument to document.cookie on purpose for test
            document.cookie = {
                toString() {
                    const expires = new Date(+new Date() + 86400 * 1000 * 100).toUTCString();
                    return 'a=b; expires=' + expires;
                },
            };
            // wait for a tick, as cookie modification happens in a promise
            await new Promise((resolve) => setTimeout(resolve, 1));
            // @ts-expect-error - cookieStore API types are missing here
            // eslint-disable-next-line no-undef
            return cookieStore.get('a');
        });
        expect(result.name).toEqual('a');
        expect(result.value).toEqual('b');
        expect(result.expires).toBeLessThan(Date.now() + 605_000_000);
    });

    test('Erroneous values do not throw', async ({ page }) => {
        await gotoAndWait(page, '/index.html');
        const result = await page.evaluate(async () => {
            document.cookie = 'a=b; expires=Wed, 21 Aug 2040 20:00:00 UTC;';

            // @ts-expect-error - Invalid argument to document.cookie on purpose for test
            document.cookie = null;

            // @ts-expect-error - Invalid argument to document.cookie on purpose for test
            document.cookie = undefined;

            // wait for a tick, as cookie modification happens in a promise
            await new Promise((resolve) => setTimeout(resolve, 1));
            // @ts-expect-error - cookieStore API types are missing here
            // eslint-disable-next-line no-undef
            return cookieStore.get('a');
        });
        expect(result.name).toEqual('a');
        expect(result.value).toEqual('b');
        expect(result.expires).toBeLessThan(Date.now() + 605_000_000);
    });
});
