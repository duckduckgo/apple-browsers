import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../types.js';
import { FreemiumPIRBannerService } from './freemiumPIRBanner.service.js';
import { reducer, useDataSubscription, useInitialData } from '../service.hooks.js';

/**
 * @typedef {import('../../types/new-tab.js').FreemiumPIRBannerData} FreemiumPIRBannerData
 * @typedef {import('../service.hooks.js').State<FreemiumPIRBannerData, undefined>} State
 * @typedef {import('../service.hooks.js').Events<FreemiumPIRBannerData, undefined>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const FreemiumPIRBannerContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {(id: string) => void} */
    dismiss: (id) => {
        throw new Error('must implement dismiss' + id);
    },
    /** @type {(id: string) => void} */
    action: (id) => {
        throw new Error('must implement action' + id);
    },
});

export const FreemiumPIRBannerDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A data provider that will use `FreemiumPIRBannerService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function FreemiumPIRBannerProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    // const [state, dispatch] = useReducer(withLog('FreemiumPIRBannerProvider', reducer), initial)
    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `FreemiumPIRBannerService` for the lifespan of this component.
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

    const action = useCallback(
        (id) => {
            service.current?.action(id);
        },
        [service],
    );

    return (
        <FreemiumPIRBannerContext.Provider value={{ state, dismiss, action }}>
            <FreemiumPIRBannerDispatchContext.Provider value={dispatch}>{props.children}</FreemiumPIRBannerDispatchContext.Provider>
        </FreemiumPIRBannerContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<FreemiumPIRBannerService>}
 */
export function useService() {
    const service = useRef(/** @type {FreemiumPIRBannerService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new FreemiumPIRBannerService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}
