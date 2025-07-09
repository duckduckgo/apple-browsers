// eslint-disable-next-line @typescript-eslint/no-unused-vars
import json from '../public/locales/en/onboarding.json';
import { TranslationContext } from '../../../shared/components/TranslationsProvider';
import { useContext } from 'preact/hooks';

/**
 * @typedef {'dock'
 *   | 'import'
 *   | 'default-browser'
 *   | 'bookmarks'
 *   | 'session-restore'
 *   | 'home-shortcut'
 *   | 'placebo-ad-blocking'
 *   | 'aggressive-ad-blocking'
 *   | 'youtube-ad-blocking'
 * } SystemValueId - Each setting that can be updated should have a unique ID listed here.
 */

/**
 * @typedef {WelcomeStep
 *   | GetStartedStep
 *   | PrivateByDefaultStep
 *   | CleanerBrowsingStep
 *   | SystemSettingsStep
 *   | CustomizeStep
 *   | SummaryStep
 *   | DockSingleStep
 *   | ImportSingleStep
 *   | MakeDefaultSingleStep
 *   | DuckPlayerSingleStep
 * } Step
 * @typedef {{ kind: 'info'; id: 'welcome' }} WelcomeStep
 * @typedef {{ kind: 'info'; id: 'getStarted' }} GetStartedStep
 * @typedef {{ kind: 'info'; id: 'privateByDefault' }} PrivateByDefaultStep
 * @typedef {{ kind: 'info'; id: 'cleanerBrowsing' }} CleanerBrowsingStep
 * @typedef {{ kind: 'settings'; id: 'systemSettings'; rows: SystemValueId[]; }} SystemSettingsStep
 * @typedef {{ kind: 'settings'; id: 'customize'; rows: SystemValueId[]; }} CustomizeStep
 * @typedef {{ kind: 'settings'; id: 'dockSingle'; rows: SystemValueId[]; }} DockSingleStep
 * @typedef {{ kind: 'settings'; id: 'importSingle'; rows: SystemValueId[]; }} ImportSingleStep
 * @typedef {{ kind: 'settings'; id: 'makeDefaultSingle'; rows: SystemValueId[]; }} MakeDefaultSingleStep
 * @typedef {{ kind: 'info'; id: 'duckPlayerSingle' }} DuckPlayerSingleStep
 * @typedef {{ kind: 'info'; id: 'summary' }} SummaryStep
 */

/** @type {Step['id'][]} */
export const EVERY_PAGE_ID = [
    'welcome',
    'getStarted',
    'privateByDefault',
    'cleanerBrowsing',
    'systemSettings',
    'customize',
    'summary',
    'dockSingle',
    'importSingle',
    'makeDefaultSingle',
    'duckPlayerSingle',
];

/** @type {Step['id'][]} */
export const DEFAULT_ORDER = ['welcome', 'getStarted', 'privateByDefault', 'cleanerBrowsing', 'systemSettings', 'customize', 'summary'];

/** @type {Step['id'][]} */
export const ALT_ORDER = [
    'welcome',
    'getStarted',
    'privateByDefault',
    'cleanerBrowsing',
    'dockSingle',
    'importSingle',
    'makeDefaultSingle',
    'customize',
    'summary',
];

/** @type {Step['id'][]} */
export const ORDER_V3 = ['welcome', 'getStarted', 'makeDefaultSingle', 'systemSettings', 'duckPlayerSingle', 'customize'];

/**
 * @typedef {BooleanSystemValue} SystemValue - values sent in messages to the host
 * @typedef {{ enabled: boolean }} BooleanSystemValue
 * @typedef {'idle' | 'accepted' | 'skipped'} UIValue
 */

/**
 * @typedef {{ kind: 'idle', error?: string } |
 *   { kind: 'executing', action: GlobalEvents } |
 *   { kind: 'fatal'; action: ErrorBoundaryEvent }
 * } Status - types to represent the state of the system
 */

/**
 * @typedef {Object} GlobalState
 * @property {import("./data").StepDefinitions} stepDefinitions
 * @property {Step} step
 * @property {Step['id'][]} order
 * @property {Step['id']} activeStep
 * @property {Step['id'] | undefined} nextStep
 * @property {number} activeRow
 * @property {boolean} activeStepVisible
 * @property {boolean} exiting
 * @property {Status} status
 * @property {Partial<Record<SystemValueId, SystemValue>>} values
 * @property {Record<SystemValueId, UIValue>} UIValues
 */

/**
 * @typedef {AdvanceEvent
 *   | TitleCompleteEvent
 *   | NextEvent
 *   | UpdateSystemValueEvent
 *   | ExecCompleteEvent
 *   | ExecErrorEvent
 *   | DismissEvent
 *   | DismisstoSettingsEvent
 *   | ErrorBoundaryEvent} GlobalEvents
 *  All the events that the UI can dispatch
 * @typedef {{ kind: "enqueue-next"; }} NextEvent
 * @typedef {{ kind: "advance" }} AdvanceEvent
 * @typedef {{ kind: "update-system-value"; id: SystemValueId; payload: SystemValue; current: boolean;}} UpdateSystemValueEvent
 * @typedef {{ kind: "exec-complete"; id: SystemValueId; payload: SystemValue }} ExecCompleteEvent
 * @typedef {{ kind: "exec-error"; id: SystemValueId; message: string }} ExecErrorEvent
 * @typedef {{ kind: "dismiss" }} DismissEvent
 * @typedef {{ kind: "dismiss-to-settings" }} DismisstoSettingsEvent
 * @typedef {{ kind: "error-boundary"; error: { message: string; id: Step['id'] }}} ErrorBoundaryEvent
 * @typedef {{ kind: "title-complete"; }} TitleCompleteEvent
 *
 */

/** @type {ImportMeta['injectName'][]} */
export const PLATFORMS = ['apple', 'windows'];

export {};

/**
 * @typedef {ReturnType<useTypedTranslation>['t']} TranslationFn
 */

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof json, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}
