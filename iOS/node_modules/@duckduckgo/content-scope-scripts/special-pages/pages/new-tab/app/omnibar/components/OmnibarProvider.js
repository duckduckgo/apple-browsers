import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../../types.js';
import { reducer, useInitialDataAndConfig, useConfigSubscription } from '../../service.hooks.js';
import { OmnibarService } from '../omnibar.service.js';

/**
 * @typedef {import('../../../types/new-tab.js').OmnibarConfig} OmnibarConfig
 * @typedef {import('../../../types/new-tab.js').SuggestionsData} SuggestionsData
 * @typedef {import('../../../types/new-tab.js').Suggestion} Suggestion
 * @typedef {import('../../../types/new-tab.js').OpenTarget} OpenTarget
 * @typedef {import('../../service.hooks.js').State<null, OmnibarConfig>} State
 */

/**
 * These are the values exposed to consumers.
 */
export const OmnibarContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {(mode: OmnibarConfig['mode']) => void} */
    setMode: () => {
        throw new Error('must implement');
    },
    /** @type {(term: string) => Promise<SuggestionsData>} */
    getSuggestions: () => {
        throw new Error('must implement');
    },
    /** @type {(cb: (data: SuggestionsData, term: string) => void) => (() => void)} */
    onSuggestions: () => {
        throw new Error('must implement');
    },
    /** @type {(params: {suggestion: Suggestion, target: OpenTarget}) => void} */
    openSuggestion: () => {
        throw new Error('must implement');
    },
    /** @type {(params: {term: string, target: OpenTarget}) => void} */
    submitSearch: () => {
        throw new Error('must implement');
    },
    /** @type {(params: {chat: string, target: OpenTarget}) => void} */
    submitChat: () => {
        throw new Error('must implement');
    },
});

export const OmnibarServiceContext = createContext(/** @type {OmnibarService|null} */ (null));

/**
 * A data provider that will use `OmnibarService` to fetch initial config only
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function OmnibarProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `OmnibarService` for the lifespan of this component.
    const service = useService();

    // get initial data and config (data will be null)
    useInitialDataAndConfig({ dispatch, service });

    // subscribe to config updates
    useConfigSubscription({ dispatch, service });

    /** @type {(mode: OmnibarConfig['mode']) => void} */
    const setMode = useCallback(
        (mode) => {
            service.current?.setMode(mode);
        },
        [service],
    );

    /** @type {(term: string) => Promise<SuggestionsData>} */
    const getSuggestions = useCallback(
        (term) => {
            if (!service.current) throw new Error('Service not available');
            return service.current.getSuggestions(term);
        },
        [service],
    );

    /** @type {(cb: (data: SuggestionsData, term: string) => void) => (() => void)} */
    const onSuggestions = useCallback(
        (cb) => {
            if (!service.current) throw new Error('Service not available');
            return service.current.onSuggestions(cb);
        },
        [service],
    );

    /** @type {(params: {suggestion: Suggestion, target: OpenTarget}) => void} */
    const openSuggestion = useCallback(
        (params) => {
            service.current?.openSuggestion(params);
        },
        [service],
    );

    /** @type {(params: {term: string, target: OpenTarget}) => void} */
    const submitSearch = useCallback(
        (params) => {
            service.current?.submitSearch(params);
        },
        [service],
    );

    /** @type {(params: {chat: string, target: OpenTarget}) => void} */
    const submitChat = useCallback(
        (params) => {
            service.current?.submitChat(params);
        },
        [service],
    );

    return (
        <OmnibarContext.Provider
            value={{
                state,
                setMode,
                getSuggestions,
                onSuggestions,
                openSuggestion,
                submitSearch,
                submitChat,
            }}
        >
            <OmnibarServiceContext.Provider value={service.current}>{props.children}</OmnibarServiceContext.Provider>
        </OmnibarContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<OmnibarService>}
 */
export function useService() {
    const service = useRef(/** @type {OmnibarService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const omnibar = new OmnibarService(ntp);
        service.current = omnibar;
        return () => {
            omnibar.destroy();
        };
    }, [ntp]);
    return service;
}
