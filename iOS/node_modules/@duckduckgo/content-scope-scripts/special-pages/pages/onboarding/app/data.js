// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { availableIcons } from './components/ListItem';
import pinningAnimation from './animations/taskbar_pinning.riv';
import importAnimation from './animations/import.riv';
import defaultAnimation from './animations/set_default.riv';

/**
 * @typedef {object} RowData
 * @property {'one-time' | 'toggle'} kind
 * @property {import('./types').SystemValueId} id
 * @property {typeof availableIcons[number]} icon
 * @property {string} title
 * @property {string} secondaryText
 * @property {string} acceptText
 * @property {string} summary
 */

/**
 * @typedef {Record<import('./types').Step['id'], import('./types').Step>} StepDefinitions
 */

/**
 * This is the information that powers the global state/nav.
 * This deliberately does not include the UI state or any strings
 * that might need translating. This is here purely as a structure that
 * the native layer can override.
 *
 * See {@link OnboardingMessages} for more details.
 *
 * For example, on Windows 10 the `systemSettings` section does not contain a 'dock' row,
 * but on Windows 11 it does.
 *
 * @type {Record<import('./types').Step['id'], import('./types').Step>}
 */
export const stepDefinitions = {
    welcome: {
        id: 'welcome',
        kind: 'info',
    },
    getStarted: {
        id: 'getStarted',
        kind: 'info',
    },
    privateByDefault: {
        id: 'privateByDefault',
        kind: 'info',
    },
    cleanerBrowsing: {
        id: 'cleanerBrowsing',
        kind: 'info',
    },
    systemSettings: {
        id: 'systemSettings',
        kind: 'settings',
        rows: ['import', 'default-browser'],
    },
    dockSingle: {
        id: 'dockSingle',
        kind: 'settings',
        rows: ['dock'],
    },
    importSingle: {
        id: 'importSingle',
        kind: 'settings',
        rows: ['import'],
    },
    makeDefaultSingle: {
        id: 'makeDefaultSingle',
        kind: 'settings',
        rows: ['default-browser'],
    },
    customize: {
        id: 'customize',
        kind: 'settings',
        rows: ['bookmarks', 'session-restore', 'home-shortcut'],
    },
    summary: {
        id: 'summary',
        kind: 'info',
    },
    duckPlayerSingle: {
        id: 'duckPlayerSingle',
        kind: 'info',
    },
};

export const stepMeta = /** @type {const} */ ({
    dockSingle: {
        rows: {
            dock: {
                kind: 'animation',
                path: pinningAnimation,
            },
        },
    },
    importSingle: {
        rows: {
            import: {
                kind: 'animation',
                path: importAnimation,
            },
        },
    },
    makeDefaultSingle: {
        rows: {
            'default-browser': {
                kind: 'animation',
                path: defaultAnimation,
            },
        },
    },
});
/**
 * Row items that do not cause system settings to be altered
 * @type {Record<string, (t: import('./types').TranslationFn) => Omit<RowData, "id" | "acceptText"> & { id: string }>}
 */
export const noneSettingsRowItems = {
    search: (t) => ({
        id: 'search',
        summary: t('row_search_summary'),
        icon: 'search.png',
        title: t('row_search_title'),
        secondaryText: t('row_search_desc'),
        kind: 'one-time',
    }),
    trackingProtection: (t) => ({
        id: 'trackingProtection',
        summary: t('row_trackingProtection_summary'),
        icon: 'shield.png',
        title: t('row_trackingProtection_title'),
        secondaryText: t('row_trackingProtection_desc'),
        kind: 'one-time',
    }),
    cookieManagement: (t) => ({
        id: 'cookieManagement',
        summary: t('row_cookieManagement_summary'),
        icon: 'cookie.png',
        title: t('row_cookieManagement_title'),
        secondaryText: t('row_cookieManagement_desc'),
        kind: 'one-time',
    }),
    fewerAds: (t) => ({
        id: 'fewerAds',
        summary: t('row_fewerAds_summary'),
        icon: 'browsing.png',
        title: t('row_fewerAds_title'),
        secondaryText: t('row_fewerAds_desc'),
        kind: 'one-time',
    }),
    duckPlayer: (t) => ({
        id: 'duckPlayer',
        summary: t('row_duckPlayer_summary'),
        icon: 'duckplayer.png',
        title: t('row_duckPlayer_title'),
        secondaryText: t('row_duckPlayer_desc'),
        kind: 'one-time',
    }),
};

/** @type {Record<import('./types').SystemValueId, (t: import('./types').TranslationFn, platform: ImportMeta['injectName']) => RowData>} */
export const settingsRowItems = {
    dock: (t, platform) => {
        const title = platform === 'apple' ? t('row_dock_macos_title') : t('row_dock_title');
        const acceptText = platform === 'apple' ? t('row_dock_macos_accept') : t('row_dock_accept');
        return {
            id: 'dock',
            icon: 'dock.png',
            title,
            secondaryText: t('row_dock_desc'),
            summary: t('row_dock_summary'),
            kind: 'one-time',
            acceptText,
        };
    },
    import: (t) => ({
        id: 'import',
        icon: 'import.png',
        title: t('row_import_title'),
        secondaryText: t('row_import_desc'),
        summary: t('row_import_summary'),
        kind: 'one-time',
        acceptText: t('row_import_accept'),
    }),
    'default-browser': (t) => ({
        id: 'default-browser',
        icon: 'switch.png',
        title: t('row_default-browser_title'),
        secondaryText: t('row_default-browser_desc'),
        summary: t('row_default-browser_summary'),
        kind: 'one-time',
        acceptText: t('row_default-browser_accept'),
    }),
    bookmarks: (t) => ({
        id: 'bookmarks',
        icon: 'bookmarks.png',
        title: t('row_bookmarks_title'),
        secondaryText: t('row_bookmarks_desc'),
        summary: t('row_bookmarks_summary'),
        kind: 'toggle',
        acceptText: t('row_bookmarks_accept'),
    }),
    'session-restore': (t) => ({
        id: 'session-restore',
        icon: 'session-restore.png',
        title: t('row_session-restore_title'),
        secondaryText: t('row_session-restore_desc'),
        summary: t('row_session-restore_summary'),
        kind: 'toggle',
        acceptText: t('row_session-restore_accept'),
    }),
    'home-shortcut': (t) => ({
        id: 'home-shortcut',
        icon: 'home.png',
        title: t('row_home-shortcut_title'),
        secondaryText: t('row_home-shortcut_desc'),
        summary: t('row_home-shortcut_summary'),
        kind: 'toggle',
        acceptText: t('row_home-shortcut_accept'),
    }),
    // Intended only for use with v3
    'placebo-ad-blocking': (t) => ({
        id: 'placebo-ad-blocking',
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('row_placebo-ad-blocking_title_v3'),
        secondaryText: t('row_ad-blocking_desc_v3'),
        summary: t('row_placebo-ad-blocking_title_v3'),
        kind: 'one-time',
        acceptText: t('row_ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
    // Intended only for use with v3
    'aggressive-ad-blocking': (t) => ({
        id: 'aggressive-ad-blocking',
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('row_aggressive-ad-blocking_title_v3'),
        secondaryText: t('row_ad-blocking_desc_v3'),
        summary: t('row_aggressive-ad-blocking_title_v3'),
        kind: 'one-time',
        acceptText: t('row_ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
    // Intended only for use with v3
    'youtube-ad-blocking': (t) => ({
        id: 'youtube-ad-blocking',
        icon: 'v3/Video-Player-Color-24.svg',
        title: t('row_youtube-ad-blocking_title_v3'),
        secondaryText: t('row_youtube-ad-blocking_desc_v3'),
        summary: t('row_youtube-ad-blocking_title_v3'),
        kind: 'one-time',
        acceptText: t('row_youtube-ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
};

/**
 * @typedef {Object} BeforeAfter
 * @property {string} btnBeforeText
 * @property {string} btnAfterText
 * @property {string} artboard
 * @property {string} inputName
 * @property {string} stateMachine
 */

/**
 * @type {Record<string, (fn: import('./types').TranslationFn) => BeforeAfter>} */
export const beforeAfterMeta = {
    /**
     * @param {import('./types').TranslationFn} t
     */
    fewerAds: (t) => ({
        btnBeforeText: t('beforeAfter_fewerAds_show'),
        btnAfterText: t('beforeAfter_fewerAds_hide'),
        artboard: 'Ad Blocking',
        inputName: 'DDG?',
        stateMachine: 'State Machine 2',
    }),
    /**
     * @param {import('./types').TranslationFn} t
     */
    duckPlayer: (t) => ({
        btnBeforeText: t('beforeAfter_duckPlayer_show'),
        btnAfterText: t('beforeAfter_duckPlayer_hide'),
        artboard: 'Duck Player',
        inputName: 'Duck Player?',
        stateMachine: 'State Machine 2',
    }),
};
