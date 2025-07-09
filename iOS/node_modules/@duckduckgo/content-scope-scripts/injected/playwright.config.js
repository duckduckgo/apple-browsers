/* global process */
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
    projects: [
        {
            name: 'windows',
            testMatch: [
                'integration-test/duckplayer.spec.js',
                'integration-test/duckplayer-remote-config.spec.js',
                'integration-test/harmful-apis.spec.js',
                'integration-test/windows-permissions.spec.js',
                'integration-test/broker-protection-tests/**/*.spec.js',
                'integration-test/breakage-reporting.spec.js',
            ],
            use: { injectName: 'windows', platform: 'windows' },
        },
        {
            name: 'apple-isolated',
            testMatch: [
                'integration-test/duckplayer.spec.js',
                'integration-test/duckplayer-remote-config.spec.js',
                'integration-test/broker-protection-tests/**/*.spec.js',
                'integration-test/favicon.spec.js',
            ],
            use: { injectName: 'apple-isolated', platform: 'macos' },
        },
        {
            name: 'apple',
            // prettier-ignore
            testMatch: [
                'integration-test/navigator-interface-insecure.js',
                'integration-test/webcompat.spec.js',
                'integration-test/message-bridge-apple.spec.js'
            ],
            use: { injectName: 'apple', platform: 'macos' },
        },
        {
            name: 'ios',
            testMatch: [
                'integration-test/duckplayer-mobile.spec.js',
                'integration-test/duckplayer-mobile-drawer.spec.js',
                'integration-test/duckplayer-native.spec.js',
            ],
            use: { injectName: 'apple-isolated', platform: 'ios', ...devices['iPhone 13'] },
        },
        {
            name: 'android',
            testMatch: [
                'integration-test/duckplayer-mobile.spec.js',
                'integration-test/duckplayer-mobile-drawer.spec.js',
                'integration-test/web-compat-android.spec.js',
                'integration-test/message-bridge-android.spec.js',
            ],
            use: { injectName: 'android', platform: 'android', ...devices['Galaxy S5'] },
        },
        {
            name: 'android-autofill-password-import',
            testMatch: ['integration-test/autofill-password-import.spec.js'],
            use: { injectName: 'android-autofill-password-import', platform: 'android', ...devices['Galaxy S5'] },
        },
        {
            name: 'chrome-mv3',
            testMatch: [
                'integration-test/remote-pages.spec.js',
                'integration-test/cookie.spec.js',
                'integration-test/fingerprint.spec.js',
                'integration-test/navigator-interface.spec.js',
                'integration-test/pages.spec.js',
                'integration-test/utils.spec.js',
                'integration-test/web-compat.spec.js',
            ],
            use: { injectName: 'chrome-mv3', platform: 'extension', ...devices['Desktop Chrome'] },
        },
        {
            name: 'firefox',
            testMatch: 'integration-test/remote-pages.spec.js',
            use: { injectName: 'firefox', platform: 'extension', ...devices['Desktop Firefox'] },
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
    /* Don't allow `.only` in CI */
    forbidOnly: Boolean(process.env.CI),
    /* Retry on CI only */
    retries: process.env.CI ? 2 : 0,
    /* Opt out of parallel tests on CI. */
    workers: process.env.CI ? 2 : undefined,
    reporter: 'html',
    /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
    webServer: {
        reuseExistingServer: true,
        ignoreHTTPSErrors: true,
        command: 'npm run bundle-entry-points && npm run serve',
        port: 3220,
    },
    use: {
        /* Maximum time each action such as `click()` can take. Defaults to 0 (no limit). */
        actionTimeout: 1000,
        /* Base URL to use in actions like `await page.goto('/')`. */
        baseURL: 'http://localhost:3220/',
        /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
        trace: 'on-first-retry',
        video: { mode: 'on-first-retry' },
    },
});
