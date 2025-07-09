/* global process */
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
    projects: [
        {
            name: 'windows',
            testMatch: [
                'duckplayer.spec.js',
                'duckplayer-screenshots.spec.js',
                'onboarding.spec.js',
                'special-error.spec.js',
                'special-error-screenshots.spec.js',
            ],
            use: {
                ...devices['Desktop Edge'],
                injectName: 'windows',
                platform: 'windows',
            },
        },
        {
            name: 'integration',
            // prettier-ignore
            testMatch: [
                'favorites.spec.js',
                'freemium-pir-banner.spec.js',
                'new-tab.spec.js',
                'new-tab.screenshots.spec.js',
                'next-steps.spec.js',
                'privacy-stats.spec.js',
                'rmf.spec.js',
                'update-notification.spec.js',
                'customizer.spec.js',
                'activity.spec.js',
                'history.spec.js',
                'history-selections.spec.js',
                'history.screenshots.spec.js',
                'protections.spec.js',
                'protections.screenshots.spec.js',
                'omnibar.spec.js',
            ],
            use: {
                ...devices['Desktop Chrome'],
                injectName: 'integration',
                platform: 'windows',
            },
        },
        {
            name: 'macos',
            testMatch: [
                'duckplayer.spec.js',
                'duckplayer-screenshots.spec.js',
                'onboarding.spec.js',
                'release-notes.spec.js',
                'special-error.spec.js',
                'special-error-screenshots.spec.js',
            ],
            use: {
                ...devices['Desktop Safari'],
                injectName: 'apple',
                platform: 'macos',
            },
        },
        {
            name: 'android',
            testMatch: ['duckplayer.spec.js', 'duckplayer-screenshots.spec.js'],
            use: {
                ...devices['Galaxy S III'],
                injectName: 'android',
                platform: 'android',
            },
        },
        {
            name: 'android-landscape',
            testMatch: ['duckplayer-screenshots.spec.js', 'duckplayer-telemetry.spec.js'],
            use: {
                ...devices['Galaxy S III landscape'],
                injectName: 'android',
                platform: 'android',
            },
        },
        {
            name: 'ios',
            testMatch: [
                'duckplayer.spec.js',
                'duckplayer-screenshots.spec.js',
                'special-error.spec.js',
                'special-error-screenshots.spec.js',
            ],
            use: {
                ...devices['iPhone 14'],
                injectName: 'apple',
                platform: 'ios',
            },
        },
    ],
    fullyParallel: !process.env.CI,
    /* Don't allow `.only` in CI */
    forbidOnly: Boolean(process.env.CI),
    /* Retry on CI only */
    retries: process.env.CI ? 2 : 0,
    /* Opt out of parallel tests on CI. */
    workers: process.env.CI ? 2 : undefined,
    /* Reporter to use. See https://playwright.dev/docs/test-reporters */
    reporter: 'html',
    // @ts-expect-error - Type 'undefined' is not assignable to type 'string'. process.env
    webServer: {
        command: process.env.PAGE ? `npm run watch -- --page ${process.env.PAGE}` : 'npm run serve',
        port: process.env.PAGE ? 8000 : 3210,
        reuseExistingServer: true,
        env: process.env,
    },
    use: {
        actionTimeout: 5000,
        trace: 'on-first-retry',
        video: { mode: 'on-first-retry' },
    },
});
