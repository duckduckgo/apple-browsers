/* global process */
import { defineConfig } from '@playwright/test';
import { dirname, join } from 'node:path';
const __dirname = dirname(new URL(import.meta.url).pathname);

export const STORAGE_STATE = join(__dirname, 'integration-test/state/yt.json');

export default defineConfig({
    projects: [
        {
            name: 'duckplayer-e2e-setup',
            testMatch: ['integration-test/duckplayer.setup.e2e.spec.js'],
            use: { injectName: 'apple-isolated', platform: 'macos' },
        },
        {
            name: 'duckplayer-e2e',
            testMatch: ['integration-test/duckplayer.e2e.spec.js'],
            use: {
                injectName: 'apple-isolated',
                platform: 'macos',
                storageState: STORAGE_STATE,
            },
            dependencies: ['duckplayer-e2e-setup'],
        },
    ],
    timeout: 30 * 1000,
    expect: {
        /**
         * Maximum time expect() should wait for the condition to be met.
         * For example in `await expect(locator).toHaveText();`
         */
        timeout: 5000,
    },
    /* Run tests in files in parallel */
    fullyParallel: !process.env.CI,
    /* Retry on CI only */
    retries: process.env.CI ? 2 : 0,
    /* Opt out of parallel tests on CI. */
    workers: process.env.CI ? 1 : undefined,
    reporter: process.env.CI ? 'github' : [['html', { open: 'never' }]],
    use: {
        /* Maximum time each action such as `click()` can take. Defaults to 0 (no limit). */
        actionTimeout: 5000,
        /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
        trace: 'on-first-retry',
    },
});
