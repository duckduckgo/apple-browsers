/**
 * @typedef {import('../types/release-notes.js').UpdateMessage} UpdateMessage
 */

const timestampInSeconds = Date.now() / 1000;

/**
 * @type {Record<UpdateMessage['status'], UpdateMessage>}
 */
export const sampleData = {
    loading: {
        status: 'loading',
        currentVersion: '1.0.1',
        lastUpdate: timestampInSeconds - 24 * 60 * 60,
    },
    loadingError: {
        status: 'loadingError',
        currentVersion: '1.0.1',
        lastUpdate: timestampInSeconds - 24 * 60 * 60,
    },
    loaded: {
        currentVersion: '1.0.1',
        latestVersion: '1.0.1',
        lastUpdate: timestampInSeconds,
        status: 'loaded',
        releaseTitle: 'May 20 2024',
        releaseNotes: [
            'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
            'Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.',
        ],
        releaseNotesPrivacyPro: [
            'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            'Privacy Pro is currently available to U.S. residents only',
        ],
    },
    updateReady: {
        currentVersion: '1.0.1',
        latestVersion: '1.2.0',
        lastUpdate: timestampInSeconds,
        status: 'updateReady',
        automaticUpdate: true,
        releaseTitle: 'June 20 2024',
        releaseNotes: [
            'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
            'Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.',
        ],
        releaseNotesPrivacyPro: [
            'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            'Privacy Pro is currently available to U.S. residents only',
        ],
    },
    criticalUpdateReady: {
        currentVersion: '1.0.1',
        latestVersion: '1.2.0',
        lastUpdate: timestampInSeconds,
        status: 'criticalUpdateReady',
        automaticUpdate: true,
        releaseTitle: 'June 20 2024',
        releaseNotes: [
            'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
            'Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.',
        ],
        releaseNotesPrivacyPro: [
            'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            'Privacy Pro is currently available to U.S. residents only',
        ],
    },
    updateError: {
        currentVersion: '1.0.1',
        latestVersion: '1.2.0',
        lastUpdate: timestampInSeconds,
        status: 'updateError',
        releaseTitle: 'June 20 2024',
        releaseNotes: [
            'Startup Boost Enabled! DuckDuckGo will now run a background task whenever you startup your computer to help it launch faster.',
            "Fixed an issue where Microsoft Teams links wouldn't open the Teams app.",
            'Improved credential autofill on websites in Dutch, French, German, Italian, Spanish, and Swedish.',
        ],
        releaseNotesPrivacyPro: [
            'Personal Information Removal update! The list of data broker sites we can scan and remove your info from is growing.',
            'Privacy Pro is currently available to U.S. residents only',
        ],
    },
    updateDownloading: {
        currentVersion: '1.0.1',
        latestVersion: '1.2.0',
        lastUpdate: timestampInSeconds,
        status: 'updateDownloading',
        downloadProgress: 0.74,
    },
    updatePreparing: {
        currentVersion: '1.0.1',
        latestVersion: '1.2.0',
        lastUpdate: timestampInSeconds,
        status: 'updatePreparing',
    },
};
