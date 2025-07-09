import { createContext, h } from 'preact';
import { useCallback, useContext, useEffect, useReducer } from 'preact/hooks';
import { usePlatformName } from './components/SettingsProvider.js';

/**
 * @typedef {import("./types.js").GlobalState} GlobalState
 * @typedef {import("./types.js").GlobalEvents} GlobalEvents
 */

export const GlobalContext = createContext(/** @type {GlobalState} */ ({}));
export const GlobalDispatch = createContext(/** @type {import("preact/hooks").Dispatch<GlobalEvents>} */ ({}));

/**
 * All application state is managed here.
 *
 * @param {GlobalState} state
 * @param {GlobalEvents} action
 * @return {GlobalState}
 */
export function reducer(state, action) {
    // console.group('reducer')
    // console.log('state', state)
    // console.log('action', action)
    // console.groupEnd()

    switch (state.status.kind) {
        case 'idle': {
            switch (action.kind) {
                case 'update-system-value': {
                    return { ...state, status: { kind: 'executing', action } };
                }
                case 'error-boundary': {
                    return { ...state, status: { kind: 'fatal', action } };
                }
                case 'title-complete': {
                    return {
                        ...state,
                        activeStepVisible: true,
                    };
                }
                case 'advance': {
                    const currentPageIndex = state.order.indexOf(state.activeStep);
                    const nextPageIndex = currentPageIndex + 1;
                    if (nextPageIndex < state.order.length) {
                        return {
                            ...state,
                            activeStep: state.order[nextPageIndex],
                            nextStep: state.order[nextPageIndex + 1],
                            activeRow: 0,
                            activeStepVisible: false,
                            exiting: false,
                            step: state.stepDefinitions[state.order[nextPageIndex]],
                        };
                    }
                    return state;
                }
                case 'enqueue-next': {
                    return {
                        ...state,
                        exiting: true,
                    };
                }
                default:
                    return state;
            }
        }
        case 'executing': {
            switch (action.kind) {
                case 'exec-complete': {
                    if (state.step.kind === 'settings') {
                        // only advance to another row if we're updating the current item.
                        // this allows us to toggle items on/off even when the row is no longer the active one
                        const currentRow = state.step.rows[state.activeRow];
                        const isCurrent = currentRow === action.id;

                        /** @type {import('./types').SystemValueId} */
                        const systemValueId = action.id;

                        // skip Duck Player onboarding step when ad blocking is enabled
                        // note: there's no UI for disabling this setting, so we never need to re-insert duckPlayerSingle into order
                        const isAdBlockingSetting =
                            systemValueId === 'placebo-ad-blocking' ||
                            systemValueId === 'aggressive-ad-blocking' ||
                            systemValueId === 'youtube-ad-blocking';
                        const nextOrder =
                            isAdBlockingSetting && action.payload.enabled
                                ? state.order.filter((step) => step !== 'duckPlayerSingle')
                                : state.order;

                        /** @type {import('./types').UIValue} */
                        const nextUIState = isCurrent && action.payload.enabled ? 'accepted' : 'skipped';

                        return {
                            ...state,
                            status: { kind: 'idle' },
                            step: {
                                // bump the step (show the next row)
                                ...state.step,
                            },
                            order: nextOrder,
                            activeRow: isCurrent ? state.activeRow + 1 : state.activeRow,
                            values: {
                                ...state.values,
                                // store the updated value in global state
                                [systemValueId]: action.payload,
                            },
                            UIValues: {
                                ...state.UIValues,
                                // store the UI state, so we know if it was skipped or not
                                [systemValueId]: nextUIState,
                            },
                        };
                    }
                    throw new Error('unimplemented');
                }
                case 'exec-error': {
                    return {
                        ...state,
                        status: { kind: 'idle', error: action.message },
                    };
                }
                default:
                    throw new Error('unhandled ' + action.kind);
            }
        }
    }
    return state;
}

/**
 * Provides navigation functionality for the application.
 * @param {Object} props - The properties for the NavigationProvider component.
 * @param {import('./types').Step['id'][]} props.order - The order of screens to display
 * @param {import("preact").ComponentChild} props.children - The children components.
 * @param {import('./data').StepDefinitions} props.stepDefinitions -
 * @param {import("./messages.js").OnboardingMessages} props.messaging - The messaging object used for communication.
 * @param {import('./types').Step['id']} [props.firstPage]
 */
export function GlobalProvider({ order, children, stepDefinitions, messaging, firstPage = 'welcome' }) {
    const [state, dispatch] = useReducer(reducer, {
        status: { kind: 'idle' },
        order,
        stepDefinitions,
        step: stepDefinitions[firstPage],
        activeStep: firstPage,
        nextStep: order[1],
        activeRow: 0,
        activeStepVisible: false,
        exiting: false,
        values: {},
        UIValues: {
            dock: 'idle',
            import: 'idle',
            'default-browser': 'idle',
            bookmarks: 'idle',
            'session-restore': 'idle',
            'home-shortcut': 'idle',
            'placebo-ad-blocking': 'idle',
            'aggressive-ad-blocking': 'idle',
            'youtube-ad-blocking': 'idle',
        },
    });

    const platform = usePlatformName();
    const proxy = useCallback(
        (/** @type {GlobalEvents} */ msg) => {
            /**
             * Regular global state updates
             */
            dispatch(msg);

            /**
             * Side effects that don't impact global state
             */
            if (msg.kind === 'advance') {
                messaging.stepCompleted({ id: state.activeStep });
            }
            if (msg.kind === 'dismiss-to-settings') {
                messaging.dismissToSettings();
            }
            if (msg.kind === 'dismiss') {
                messaging.dismissToAddressBar();
            }
        },
        [state, messaging],
    );

    // handle *fatal* state (from error boundary)
    useEffect(() => {
        if (state.status.kind !== 'fatal') return;
        const { error } = state.status.action;
        messaging.reportPageException(error);
    }, [state.status.kind, messaging]);

    // handle 'update-system-value' messages from the UI
    useEffect(() => {
        if (state.status.kind !== 'executing') return;
        if (state.status.action.kind !== 'update-system-value') throw new Error('only update-system-value is currently supported');

        /** @type {import('./types').UpdateSystemValueEvent} */
        const action = state.status.action;

        handleSystemSettingUpdate(action, messaging, platform)
            // eslint-disable-next-line promise/prefer-await-to-then
            .then((/** @type {import('./types').SystemValue} */ payload) => {
                dispatch({
                    kind: 'exec-complete',
                    id: action.id,
                    payload,
                });
            })
            // eslint-disable-next-line promise/prefer-await-to-then
            .catch((e) => {
                const message = e?.message || 'unknown error';
                dispatch({ kind: 'exec-error', id: action.id, message });
            });
    }, [state.status.kind, messaging]);

    return (
        <GlobalContext.Provider value={state}>
            <GlobalDispatch.Provider value={proxy}>{children}</GlobalDispatch.Provider>
        </GlobalContext.Provider>
    );
}

/**
 * A single place to handle all messages from the UI that update system settings.
 *
 * @param {import('./types').UpdateSystemValueEvent} action
 * @param {import("./messages").OnboardingMessages} messaging
 * @param {ImportMeta['platform']} platform
 */
async function handleSystemSettingUpdate(action, messaging, platform) {
    const { id, payload } = action;
    switch (id) {
        case 'bookmarks': {
            messaging.setBookmarksBar(payload);
            return payload;
        }
        case 'session-restore': {
            messaging.setSessionRestore(payload);
            return payload;
        }
        case 'home-shortcut': {
            messaging.setShowHomeButton(payload);
            return payload;
        }
        case 'placebo-ad-blocking':
        case 'aggressive-ad-blocking':
        case 'youtube-ad-blocking': {
            messaging.setAdBlocking(payload);
            return payload;
        }
        case 'dock': {
            // if a users presses 'skip' and we remove from the dock, can it actually be un-done? (eg: placed back?)
            if (payload.enabled) {
                await messaging.requestDockOptIn();
                return { enabled: true };
            }
            break;
        }
        case 'import': {
            if (payload.enabled) {
                if (platform === 'macos') {
                    return await messaging.requestImport();
                }

                // enabled means we've launched a native UI, not that imports actually occurred
                // todo: can we support both? if a user presses cancel, should we detect and allow them to try again?
                await messaging.requestImport();
                return { enabled: true };
            }
            break;
        }
        case 'default-browser': {
            if (payload.enabled) {
                // enabled means we've launched a native UI, not that we actually agreed
                // todo: can we support both? if a user presses cancel, should we detect and allow them to try again?
                await messaging.requestSetAsDefault();
                return { enabled: true };
            }
            break;
        }
    }
    if ('value' in payload) {
        return { enabled: payload.enabled, value: payload.value };
    }
    return { enabled: payload.enabled };
}

export function useGlobalState() {
    return useContext(GlobalContext);
}

export function useGlobalDispatch() {
    return useContext(GlobalDispatch);
}
