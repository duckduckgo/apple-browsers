import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../types.js';
import { RMFService } from './rmf.service.js';
import { reducer, useDataSubscription, useInitialData } from '../service.hooks.js';

/**
 * @typedef {import('../../types/new-tab.js').RMFData} RMFData
 * @typedef {import('../service.hooks.js').State<RMFData, undefined>} State
 * @typedef {import('../service.hooks.js').Events<RMFData, undefined>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const RMFContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {(id: string) => void} */
    dismiss: (id) => {
        throw new Error('must implement dismiss' + id);
    },
    /** @type {(id: string) => void} */
    primaryAction: (id) => {
        throw new Error('must implement primaryAction' + id);
    },
    /** @type {(id: string) => void} */
    secondaryAction: (id) => {
        throw new Error('must implement secondaryAction' + id);
    },
});

export const RMFDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A data provider that will use `RMFService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function RMFProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    // const [state, dispatch] = useReducer(withLog('RMFProvider', reducer), initial)
    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `RMFService` for the lifespan of this component.
    const service = useService();

    // get initial data
    useInitialData({ dispatch, service });

    // subscribe to data updates
    useDataSubscription({ dispatch, service });

    // todo(valerie): implement onDismiss in the service
    const dismiss = useCallback(
        (id) => {
            console.log('onDismiss');
            service.current?.dismiss(id);
        },
        [service],
    );

    const primaryAction = useCallback(
        (id) => {
            service.current?.primaryAction(id);
        },
        [service],
    );

    const secondaryAction = useCallback(
        (id) => {
            console.log('secondaryAction');
            service.current?.secondaryAction(id);
        },
        [service],
    );

    return (
        <RMFContext.Provider value={{ state, dismiss, primaryAction, secondaryAction }}>
            <RMFDispatchContext.Provider value={dispatch}>{props.children}</RMFDispatchContext.Provider>
        </RMFContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<RMFService>}
 */
export function useService() {
    const service = useRef(/** @type {RMFService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new RMFService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}
