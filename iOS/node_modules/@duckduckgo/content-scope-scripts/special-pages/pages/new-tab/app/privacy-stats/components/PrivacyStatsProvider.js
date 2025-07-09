import { createContext, h } from 'preact';
import { useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../../types.js';
import { PrivacyStatsService } from '../privacy-stats.service.js';
import { reducer, useDataSubscription, useInitialData } from '../../service.hooks.js';

/**
 * @typedef {import('../../../types/new-tab.ts').PrivacyStatsData} PrivacyStatsData
 * @typedef {import('../../../types/new-tab.ts').Expansion} Expansion
 * @typedef {import('../../service.hooks.js').State<PrivacyStatsData, null>} State
 * @typedef {import('../../service.hooks.js').Events<PrivacyStatsData, null>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const PrivacyStatsContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
});

export const PrivacyStatsDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A data provider that will use `PrivacyStatsService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function PrivacyStatsProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    // const [state, dispatch] = useReducer(withLog('PrivacyStatsProvider', reducer), initial)
    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `PrivacyStatsService` for the lifespan of this component.
    const service = useService();

    // get initial data
    useInitialData({ dispatch, service });

    // subscribe to data updates
    useDataSubscription({ dispatch, service });

    return (
        <PrivacyStatsContext.Provider value={{ state }}>
            <PrivacyStatsDispatchContext.Provider value={dispatch}>{props.children}</PrivacyStatsDispatchContext.Provider>
        </PrivacyStatsContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<PrivacyStatsService>}
 */
export function useService() {
    const service = useRef(/** @type {PrivacyStatsService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new PrivacyStatsService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}
