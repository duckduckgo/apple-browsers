/* global process */
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { chromium, firefox } from '@playwright/test';
import { fork } from 'node:child_process';
import { polyfillProcessGlobals } from '../../unit-test/helpers/polyfill-process-globals.js';

const DATA_DIR_PREFIX = 'ddg-temp-';

/**
 * @import {PlaywrightTestArgs, PlaywrightTestOptions, PlaywrightWorkerArgs, PlaywrightWorkerOptions, TestType} from "@playwright/test"
 */

/**
 * A single place
 * @param {typeof import("@playwright/test").test} test
 * @return {TestType<PlaywrightTestArgs & PlaywrightTestOptions & PlaywrightWorkerArgs & PlaywrightWorkerOptions & { altServerPort: number }, {}>}
 */
export function testContextForExtension(test) {
    return test.extend({
        context: async ({ browserName }, use) => {
            const tmpDirPrefix = join(tmpdir(), DATA_DIR_PREFIX);
            const dataDir = mkdtempSync(tmpDirPrefix);
            const browserTypes = { chromium, firefox };
            const cleanupGlobals = polyfillProcessGlobals();

            const launchOptions = {
                devtools: true,
                headless: false,
                viewport: {
                    width: 1920,
                    height: 1080,
                },
                args: ['--disable-extensions-except=integration-test/extension', '--load-extension=integration-test/extension'],
            };

            const context = await browserTypes[browserName].launchPersistentContext(dataDir, launchOptions);

            // actually run the tests
            await use(context);

            // clean up globals
            cleanupGlobals();

            // clean up
            await context.close();

            // Clean up temporary data directory
            rmSync(dataDir, { recursive: true, force: true });
        },
        altServerPort: async ({ browserName }, use) => {
            console.log('browserName:', browserName);
            const serverScript = fork('./scripts/server.mjs', {
                env: {
                    ...process.env,
                    SERVER_DIR: 'integration-test/test-pages',
                    SERVER_PORT: '8383',
                },
            });
            const opened = new Promise((resolve, reject) => {
                serverScript.on('message', (/** @type {any} */ resp) => {
                    if (typeof resp.port === 'number') {
                        resolve(resp.port);
                    } else {
                        reject(resp.port);
                    }
                });
            });
            const closed = new Promise((resolve, reject) => {
                serverScript.on('close', (err) => {
                    if (err) {
                        reject(new Error('server did not exit, code: ' + err));
                    } else {
                        resolve(null);
                    }
                });
                serverScript.on('error', () => {
                    reject(new Error('server errored'));
                });
            });

            const port = await opened;
            await use(port);
            serverScript.kill();
            await closed;
        },
    });
}

/**
 * A wrapper around page.goto() that supports sending additional
 * arguments to content-scope's init methods + waits for a known
 * indicators to avoid race conditions
 *
 * @param {import("@playwright/test").Page} page
 * @param {string} urlString
 * @param {Record<string, any>} [args]
 * @param {string|null} [evalBeforeInit]
 * @param {"extension" | "script"} [kind] - if 'extension', the script will be loaded separately. if 'script' we'll append a script tag
 * @returns {Promise<void>}
 */
export async function gotoAndWait(page, urlString, args = {}, evalBeforeInit = null, kind = 'extension') {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const [_, search] = urlString.split('?');
    const searchParams = new URLSearchParams(search);

    // Append the flag so that the script knows to wait for incoming args.
    searchParams.append('wait-for-init-args', 'true');

    await page.goto(urlString + '?' + searchParams.toString());

    if (kind === 'script') {
        await page.addScriptTag({
            url: './build/contentScope.js',
        });
    }

    // wait until contentScopeFeatures.load() has completed
    await page.waitForFunction(() => {
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        return window.__content_scope_status === 'loaded';
    });

    if (evalBeforeInit) {
        await page.evaluate(evalBeforeInit);
    }

    const evalString = `
        ;(() => {
            const detail = ${JSON.stringify(args)}
            const evt = new CustomEvent('content-scope-init-args', { detail })
            document.dispatchEvent(evt);
        })();
    `;

    await page.evaluate(evalString);

    // wait until contentScopeFeatures.init(args) has completed
    await page.waitForFunction(() => {
        window.dispatchEvent(new Event('content-scope-init-complete'));
        // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
        return window.__content_scope_status === 'initialized';
    });
}
