import { test } from '@playwright/test';
import { OnboardingPage } from './onboarding.js';

test.describe('onboarding', () => {
    test('initial handshake', async ({ page }, workerInfo) => {
        const onboarding = OnboardingPage.create(page, workerInfo);
        await onboarding.reducedMotion();
        await onboarding.darkMode();
        await onboarding.openPage();
        await onboarding.didSendInitialHandshake();
    });
    test('can be skipped in development', async ({ page }, workerInfo) => {
        const onboarding = OnboardingPage.create(page, workerInfo);
        await onboarding.reducedMotion();
        await onboarding.darkMode();
        await onboarding.openPage();
        await onboarding.skipsOnboarding();
        await onboarding.didDismissToSearch();
    });
    test('step pixels', async ({ page }, workerInfo) => {
        const onboarding = OnboardingPage.create(page, workerInfo);
        await onboarding.reducedMotion();
        await onboarding.darkMode();
        await onboarding.openPage();
        await onboarding.getStarted();
        await onboarding.didSendStepCompletedMessages();
    });
    test('exception handling', async ({ page }, workerInfo) => {
        const onboarding = OnboardingPage.create(page, workerInfo);
        await onboarding.reducedMotion();
        await onboarding.openPage({ env: 'app', page: 'welcome', willThrow: true });
        await onboarding.handlesFatalException();
    });
    test.describe('Given I am on the make default step', () => {
        test('Then "Play YouTube without targeted ads" appears when ad blocking is enabled (placebo variant)', async ({
            page,
        }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'placebo-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'makeDefaultSingle' });
            await onboarding.checkYouTubeText(false);
        });
        test('Then "Watch YouTube ad-free" appears when ad blocking is enabled (aggressive variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'aggressive-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'makeDefaultSingle' });
            await onboarding.checkYouTubeText(true);
        });
        test('Then "Watch YouTube ad-free" appears when ad blocking is enabled (YouTube variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'youtube-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'makeDefaultSingle' });
            await onboarding.checkYouTubeText(true);
        });
    });
    test.describe('Given I am on the summary step', () => {
        test('Then I can exit to search', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'summary' });
            await onboarding.choseToStartBrowsing();
            await onboarding.didDismissToSearch();
        });
        test('Then I can open settings', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'summary' });
            await onboarding.didDismissToSettings();
        });
    });
    test.describe('Given I am on the system settings step', () => {
        test('Then I can pin DuckDuckGo to my taskbar', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.keepInTaskbar();
        });
        test('Then I can turn on ad blocking (placebo variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'placebo-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.enableEnhancedAdBlocking();
        });
        test('Then I can skip ad blocking (placebo variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'placebo-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.skipAdBlocking();
        });
        test('Then I can turn on ad blocking (aggressive variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'aggressive-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.enableEnhancedAdBlocking();
        });
        test('Then I can skip ad blocking (aggresive variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'aggressive-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.skipAdBlocking();
        });
        test('Then I can turn on ad blocking (YouTube variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'youtube-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.enableYouTubeAdBlocking();
        });
        test('Then I can skip ad blocking (YouTube variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'youtube-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.skipYouTubeAdBlocking();
        });
        test('Then I can skip all', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'systemSettings' });
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await onboarding.skippedCurrent();
            await page.getByRole('button', { name: 'Next' }).click();
            await page.getByRole('heading', { name: 'Customize your experience' }).waitFor();
        });
    });
    test.describe('Given I am on the customize step', () => {
        test('Then I can see additional information about the steps', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'customize' });
            await onboarding.hasAdditionalInformation();
        });
        test('When I choose to show the bookmarks bar', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'customize' });

            // ▶️ Then the bookmarks bar shows
            await onboarding.showBookmarksBar();
        });
        test('When I have skipped bookmarks on the customize step', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'customize' });
            await onboarding.skippedBookmarksBar();

            // ▶️ Then I can toggle it afterward
            await onboarding.canToggleBookmarksBar();
        });
        test('When I have choosen to show the home button', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'customize' });

            // skipped first 2
            await onboarding.skippedBookmarksBar();
            await onboarding.skippedSessionRestore();

            await onboarding.showHomeButton();
        });
        test('When I have skipped home button', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            await onboarding.reducedMotion();
            await onboarding.openPage({ env: 'app', page: 'customize' });

            // skipped all
            await onboarding.skippedBookmarksBar();
            await onboarding.skippedSessionRestore();
            await onboarding.skippedShowHomeButton();

            await onboarding.canToggleHomeButton();
        });
    });
    test.describe('v2', () => {
        test('shows v2 flow', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        // this 'dock' is not part of the default
                        rows: ['dock', 'import', 'default-browser'],
                    },
                },
                env: 'development',
                order: 'v2',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV2();
        });
        test('shows v2 flow without pinning step', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        // this 'dock' is not part of the default
                        rows: ['dock', 'import', 'default-browser'],
                    },
                },
                env: 'development',
                order: 'v2',
                exclude: ['dockSingle'],
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV2WithoutDock();
        });
    });
    test.describe('v3', () => {
        test('shows v3 flow', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: null,
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3();
        });
        test('shows v3 flow without system settings step', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: null,
                order: 'v3',
                exclude: ['systemSettings'],
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3WithoutSettings();
        });
        test('shows v3 flow with ad blocking', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'aggressive-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3WithAdBlockingEnabled('ad-blocking');
        });
        test('shows v3 flow with ad blocking disabled', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'aggressive-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3WithAdBlockingDisabled();
        });
        test('shows v3 flow with ad blocking (YouTube variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'youtube-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3WithAdBlockingEnabled('youtube-ad-blocking');
        });
        test('shows v3 flow with ad blocking disabled (YouTube variant)', async ({ page }, workerInfo) => {
            const onboarding = OnboardingPage.create(page, workerInfo);
            onboarding.withInitData({
                stepDefinitions: {
                    systemSettings: {
                        rows: ['dock', 'import', 'youtube-ad-blocking'],
                    },
                },
                order: 'v3',
            });
            await onboarding.reducedMotion();
            await onboarding.darkMode();
            await onboarding.openPage();
            await onboarding.completesOrderV3WithAdBlockingDisabled();
        });
        test.describe('Given I am on the settings step', () => {
            test('When I have choosen to add to dock/taskbar', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'systemSettings' });

                // ▶️ Then I can add to dock/taskbar
                await onboarding.keepInTaskbar();
            });
            test('When I have skipped add to dock/taskbar', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'systemSettings' });

                // And I have skipped that step
                await onboarding.skippedCurrent();

                // ▶️ Then I can add it afterwards
                await onboarding.keepInTaskbar();
            });
            test('When I choose to import bookmarks and passwords', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'systemSettings' });
                await onboarding.skippedCurrent();

                // ▶️ Then I can import the data
                await onboarding.importUserData();
            });
            test('When I have skipped import on the customize step', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'systemSettings' });
                await onboarding.skippedCurrent();

                // And I have skipped that step
                await onboarding.skippedCurrent();

                // ▶️ Then I can choose to import afterwards
                await onboarding.importUserData();
            });
            test('When the import step has failed on macOS', async ({ page }, workerInfo) => {
                test.skip(workerInfo.project.name !== 'macos');

                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withMockData({
                    init: {
                        stepDefinitions: null,
                        order: 'v3',
                    },
                    requestImport: { enabled: false },
                });

                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'systemSettings' });
                await onboarding.skippedCurrent();

                // ▶️ Then I can still see the import button
                await onboarding.importUserDataFailedGracefully();
            });
        });
        test.describe('Given I am on the customize step', () => {
            test('Then I can see additional information about the steps', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });
                await onboarding.hasAdditionalInformationV3();
            });
            test('When I choose to show the bookmarks bar', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });

                // ▶️ Then the bookmarks bar shows
                await onboarding.showBookmarksBar();
            });
            test('When I have skipped bookmarks on the customize step', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });
                await onboarding.skippedBookmarksBar();

                // ▶️ Then I can toggle it afterward
                await onboarding.canToggleBookmarksBar();
            });
            test('When I choose to restore previous session', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });
                await onboarding.skippedBookmarksBar();

                // ▶️ Then the restore session bar shows
                await onboarding.restoreSession();
            });
            test('When I have skipped restore session on the customize step', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });
                await onboarding.skippedBookmarksBar();
                await onboarding.skippedSessionRestore();

                // ▶️ Then I can toggle it afterward
                await onboarding.canToggleRestoreSession();
            });
            test('When I have choosen to show the home button', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });

                // skipped first 2
                await onboarding.skippedBookmarksBar();
                await onboarding.skippedSessionRestore();

                // ▶️ Then the home button bar shows
                await onboarding.showHomeButton();
            });
            test('When I have skipped home button', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });

                // skipped all
                await onboarding.skippedBookmarksBar();
                await onboarding.skippedSessionRestore();
                await onboarding.skippedShowHomeButton();

                // ▶️ Then I can toggle it afterward
                await onboarding.canToggleHomeButton();
            });
            test('I can start browsing', async ({ page }, workerInfo) => {
                const onboarding = OnboardingPage.create(page, workerInfo);
                onboarding.withInitData({
                    stepDefinitions: null,
                    order: 'v3',
                });
                await onboarding.reducedMotion();
                await onboarding.openPage({ env: 'app', page: 'customize' });

                // skipped all
                await onboarding.skippedBookmarksBar();
                await onboarding.skippedSessionRestore();
                await onboarding.skippedShowHomeButton();

                // ▶️ Then I can toggle it afterward
                await onboarding.startBrowsing();
            });
        });
    });
});
