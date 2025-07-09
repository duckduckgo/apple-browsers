import { h } from 'preact';
import { Launch, Replay } from '../../components/Icons';
import { MakeDefaultStep } from './MakeDefaultStep';
import { DuckPlayerStep } from './DuckPlayerStep';
import { ElasticButton } from './ElasticButton';
import { Timeout } from '../Timeout';
import { SettingsStep } from './SettingsStep';

/**
 * This sets up individual steps in the v3 (highlights) version of onboarding
 *
 * See `./data-types.js` for documentation on parameters {StepConfigParams}
 * and return values {StepConfig}
 */

/** @type {Record<import('./data-types').StepsV3, (params: import('./data-types').StepConfigParams) => import('./data-types').StepConfig>} */
export const stepsConfig = {
    welcome: ({ t, advance }) => {
        return {
            variant: 'plain',
            heading: {
                title: t('welcome_title'),
                speechBubble: false,
                children: <Timeout onComplete={advance} ignore={true} />,
            },
        };
    },
    getStarted: ({ t, advance }) => {
        return {
            variant: 'plain',
            heading: {
                title: t('getStarted_title_v3', { newline: '\n' }).split('{paragraph}'),
                speechBubble: true,
                children: <ElasticButton onClick={advance} text={t('getStartedButton_v3')} />,
            },
        };
    },
    makeDefaultSingle: ({ t, globalState, advance, enableSystemValue }) => {
        const { UIValues } = globalState;
        const isIdle = UIValues['default-browser'] === 'idle';

        return {
            variant: 'box',
            heading: {
                title: isIdle ? t('protectionsActivated_title') : t('makeDefaultAccept_title'),
                speechBubble: true,
            },
            dismissButton: isIdle
                ? {
                      text: t('skipButton'),
                      handler: advance,
                  }
                : null,
            acceptButton: isIdle
                ? {
                      text: t('makeDefaultButton'),
                      handler: () => enableSystemValue('default-browser'),
                  }
                : {
                      text: t('nextButton'),
                      handler: advance,
                  },
            content: <MakeDefaultStep />,
        };
    },
    systemSettings: ({ t, globalState, advance }) => {
        const { step, activeRow } = globalState;
        const isDone = activeRow >= /** @type {import('../../types').SystemSettingsStep} */ (step).rows.length;

        return {
            variant: 'box',
            heading: {
                title: t('systemSettings_title_v3'),
                subtitle: t('systemSettings_subtitle_v3'),
                speechBubble: true,
            },
            acceptButton: isDone
                ? {
                      text: t('nextButton'),
                      handler: advance,
                  }
                : null,
            content: <SettingsStep data={settingsRowItems} />,
        };
    },
    duckPlayerSingle: ({ t, advance, beforeAfter }) => {
        const beforeAfterState = beforeAfter.get();
        const longestText = [t('beforeAfter_duckPlayer_show'), t('beforeAfter_duckPlayer_hide')].reduce((acc, cur) => {
            return cur.length > acc.length ? cur : acc;
        });

        return {
            variant: 'box',
            heading: {
                title: t('duckPlayer_title'),
                subtitle: t('duckPlayer_subtitle'),
                speechBubble: true,
            },
            dismissButton: {
                startIcon: <Replay direction={beforeAfterState === 'before' ? 'forward' : 'backward'} />,
                text: beforeAfterState === 'before' ? t('beforeAfter_duckPlayer_show') : t('beforeAfter_duckPlayer_hide'),
                longestText,
                handler: () => beforeAfter.toggle(),
            },
            acceptButton: {
                text: t('nextButton'),
                handler: advance,
            },
            content: <DuckPlayerStep />,
        };
    },
    customize: ({ t, globalState, dismiss }) => {
        const { step, activeRow } = globalState;
        const isDone = activeRow >= /** @type {import('../../types').CustomizeStep} */ (step).rows.length;

        return {
            variant: 'box',
            heading: {
                title: t('customize_title_v3'),
                subtitle: t('customize_subtitle_v3'),
                speechBubble: true,
            },
            acceptButton: isDone
                ? {
                      text: t('startBrowsing'),
                      endIcon: <Launch />,
                      handler: dismiss,
                  }
                : null,
            content: <SettingsStep data={settingsRowItems} />,
        };
    },
};

/**
 * @typedef {object} RowData
 * @property {'one-time' | 'toggle'} kind
 * @property {import('../../types').SystemValueId} id
 * @property {typeof import('../../components/ListItem').availableIcons[number]} icon
 * @property {string} title
 * @property {string} [secondaryText]
 * @property {string} acceptText
 * @property {'primary'|'secondary'} [accepButtonVariant]
 * @property {string} [acceptTextRecall] - Shown if a user chooses to skip that step. If undefined,
 * @property acceptText is shown.
 */

/** @type {Record<import('../../types').SystemValueId, (t: import('../../types').TranslationFn, platform: ImportMeta['platform']) => RowData>} */
export const settingsRowItems = {
    'default-browser': (t) => ({
        id: 'default-browser',
        icon: 'v3/Browser-Default-Color-24.svg',
        title: t('row_default-browser_title_v3'),
        kind: 'one-time',
        acceptText: t('row_default-browser_accept'),
        accepButtonVariant: 'primary',
    }),
    import: (t) => ({
        id: 'import',
        icon: 'v3/Import-Color-24.svg',
        title: t('row_import_title_v3'),
        secondaryText: t('row_import_summary_v3'),
        kind: 'one-time',
        acceptText: t('row_import_accept_v3'),
        acceptTextRecall: t('row_import_accept'),
        accepButtonVariant: 'primary',
    }),
    dock: (t, platform) => {
        const title = platform === 'macos' ? t('row_dock_title_v3') : t('row_taskbar_title_v3');
        const acceptText = platform === 'macos' ? t('row_dock_macos_accept') : t('row_dock_accept');
        const secondaryText = platform === 'macos' ? t('row_dock_summary_v3') : t('row_taskbar_summary_v3');

        return {
            id: 'dock',
            icon: 'v3/Add-To-Dock-Color-24.svg',
            title,
            secondaryText,
            kind: 'one-time',
            acceptText,
            accepButtonVariant: 'primary',
        };
    },
    bookmarks: (t) => ({
        id: 'bookmarks',
        icon: 'v3/Bookmark-Favorite-Color-24.svg',
        title: t('row_bookmarks_title_v3'),
        kind: 'toggle',
        acceptText: t('row_bookmarks_accept'),
        accepButtonVariant: 'secondary',
    }),
    'session-restore': (t) => ({
        id: 'session-restore',
        icon: 'v3/Session-Restore-Color-24.svg',
        title: t('row_session-restore_title_v3'),
        kind: 'toggle',
        acceptText: t('row_session-restore_accept'),
        accepButtonVariant: 'secondary',
    }),
    'home-shortcut': (t) => ({
        id: 'home-shortcut',
        icon: 'v3/Home-Color-24.svg',
        title: t('row_home-shortcut_title_v3'),
        kind: 'toggle',
        acceptText: t('row_home-shortcut_accept'),
        accepButtonVariant: 'secondary',
    }),
    'placebo-ad-blocking': (t) => ({
        id: 'placebo-ad-blocking',
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('row_placebo-ad-blocking_title_v3'),
        secondaryText: t('row_ad-blocking_desc_v3'),
        kind: 'one-time',
        acceptText: t('row_ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
    'aggressive-ad-blocking': (t) => ({
        id: 'aggressive-ad-blocking',
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('row_aggressive-ad-blocking_title_v3'),
        secondaryText: t('row_ad-blocking_desc_v3'),
        kind: 'one-time',
        acceptText: t('row_ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
    'youtube-ad-blocking': (t) => ({
        id: 'youtube-ad-blocking',
        icon: 'v3/Ads-Blocked-Color-24.svg',
        title: t('row_youtube-ad-blocking_title_v3'),
        secondaryText: t('row_youtube-ad-blocking_desc_v3'),
        kind: 'one-time',
        acceptText: t('row_youtube-ad-blocking_accept_v3'),
        accepButtonVariant: 'primary',
    }),
};

export const stepDefinitions = {
    systemSettings: {
        id: 'systemSettings',
        kind: 'settings',
        rows: ['dock', 'import'],
    },
    customize: {
        id: 'customize',
        kind: 'settings',
        rows: ['bookmarks', 'session-restore', 'home-shortcut'],
    },
};
