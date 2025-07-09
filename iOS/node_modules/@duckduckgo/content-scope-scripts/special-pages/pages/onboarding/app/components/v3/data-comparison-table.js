/**
 * @enum {string}
 * @readonly
 */
export const SupportStatus = {
    NOT_SUPPORTED: 'notSupported',
    PARTIAL_SUPPORT: 'partialSupport',
    FULL_SUPPORT: 'fullSupport',
};

// prettier-ignore
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const tableIcons = /** @type {const} */ ([
    'v3/Add-To-Dock-Color-24.svg',
    'v3/Ads-Blocked-Color-24.svg',
    'v3/Bookmark-Favorite-Color-24.svg',
    'v3/Browser-Default-Color-24.svg',
    'v3/Cookie-Blocked-Color-24.svg',
    'v3/Find-Search-Color-24.svg',
    'v3/Fire-Color-24.svg',
    'v3/Home-Color-24.svg',
    'v3/Import-Color-24.svg',
    'v3/Session-Restore-Color-24.svg',
    'v3/Shield-Color-24.svg',
    'v3/Video-Player-Color-24.svg',
]);

export const tableIconPrefix = 'assets/img/steps/';

/** @typedef {{ icon: tableIcons[number], title: string, statuses: Record<'chrome'|'safari'|'ddg', SupportStatus> }} FeatureSupportData */

/**
 * Comparison table matrix
 *
 * Safari was removed from the latest comparison table layout. Keeping it the data just in case it comes back.
 *
 * @type {(t: ReturnType<typeof import('../../types')['useTypedTranslation']>['t'], adBlockingEnabled?: boolean) => FeatureSupportData[]}
 */
export const comparisonTableData = (t, adBlockingEnabled = false) => [
    {
        icon: 'v3/Find-Search-Color-24.svg',
        title: t('comparison_searchPrivately'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.NOT_SUPPORTED,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
    {
        icon: 'v3/Shield-Color-24.svg',
        title: t('comparison_blockTrackers'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.PARTIAL_SUPPORT,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
    {
        icon: 'v3/Cookie-Blocked-Color-24.svg',
        title: t('comparison_blockCookies'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.NOT_SUPPORTED,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
    {
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('comparison_blockAds'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.NOT_SUPPORTED,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
    {
        icon: 'v3/Fire-Color-24.svg',
        title: t('comparison_eraseData'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.NOT_SUPPORTED,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
    {
        icon: 'v3/Video-Player-Color-24.svg',
        title: adBlockingEnabled ? t('comparison_youtubeAdFree') : t('comparison_privateYoutube'),
        statuses: {
            chrome: SupportStatus.NOT_SUPPORTED,
            safari: SupportStatus.NOT_SUPPORTED,
            ddg: SupportStatus.FULL_SUPPORT,
        },
    },
];
