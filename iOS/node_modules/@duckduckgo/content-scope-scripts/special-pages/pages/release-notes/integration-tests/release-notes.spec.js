import { test } from '@playwright/test';
import { ReleaseNotesPage } from './release-notes.js';

test.describe('release-notes', () => {
    test('initial handshake', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.darkMode();
        await releaseNotes.openPage();
        await releaseNotes.didSendInitialHandshake();
    });

    test('exception handling', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app', willThrow: true });
        await releaseNotes.handlesFatalException();
    });

    test('shows loading state', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesLoading();
        await releaseNotes.didShowLoadingState();
    });

    test('shows loading error state', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesLoadingError();
        await releaseNotes.didShowLoadingErrorState();
    });

    test('shows downloading update state', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateDownloading();
        await releaseNotes.didShowUpdateDownloadingState();
    });

    test('shows preparing update state', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdatePreparing();
        await releaseNotes.didShowUpdatePreparingState();
    });

    test('shows up-to-date state without Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesLoadedWithoutPrivacyPro();
        await releaseNotes.didShowUpToDateState();
        await releaseNotes.didShowReleaseNotesListWithoutPrivacyPro();
    });

    test('shows up-to-date state with Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesLoaded();
        await releaseNotes.didShowUpToDateState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('shows update ready state without Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateReadyWithoutPrivacyPro();
        await releaseNotes.didShowAutomaticUpdateReadyState();
        await releaseNotes.didShowReleaseNotesListWithoutPrivacyPro();
    });

    test('shows update ready state for manual update', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesManualUpdateReady();
        await releaseNotes.didShowManualUpdateReadyState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('shows update ready state with Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateReady();
        await releaseNotes.didShowAutomaticUpdateReadyState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('shows critical update ready state', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesCriticalUpdateReady();
        await releaseNotes.didShowAutomaticCriticalUpdateReadyState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('shows critical update ready state for manual update', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesManualCriticalUpdateReady();
        await releaseNotes.didShowManualCriticalUpdateReadyState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('shows update error state without Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateErrorWithoutPrivacyPro();
        await releaseNotes.didShowUpdateErrorState();
        await releaseNotes.didShowReleaseNotesListWithoutPrivacyPro();
    });

    test('shows update error state with Privacy Pro notes', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateError();
        await releaseNotes.didShowUpdateErrorState();
        await releaseNotes.didShowReleaseNotesList();
    });

    test('sends restart click to browser', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateReady();
        await releaseNotes.didRequestRestart();
    });

    test('sends retry update click to browser', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesUpdateError();
        await releaseNotes.didRequestRetryUpdate();
    });

    test('sends retry getting release notes click to browser', async ({ page }, workerInfo) => {
        const releaseNotes = ReleaseNotesPage.create(page, workerInfo);
        await releaseNotes.reducedMotion();
        await releaseNotes.openPage({ env: 'app' });
        await releaseNotes.releaseNotesLoadingError();
        await releaseNotes.didRequestRetryGettingReleaseNotes();
    });
});
