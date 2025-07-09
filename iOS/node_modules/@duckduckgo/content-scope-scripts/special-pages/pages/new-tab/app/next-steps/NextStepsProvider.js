import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../types.js';
import { NextStepsService } from './next-steps.service.js';
import { reducer, useConfigSubscription, useDataSubscription, useInitialDataAndConfig } from '../service.hooks.js';

/**
 * @typedef {import('../../types/new-tab.js').NextStepsData} NextStepsData
 * @typedef {import('../../types/new-tab.js').NextStepsConfig} NextStepsConfig
 * @typedef {import('../service.hooks.js').State<NextStepsData, NextStepsConfig>} State
 * @typedef {import('../service.hooks.js').Events<NextStepsData, NextStepsConfig>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const NextStepsContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {() => void} */
    toggle: () => {
        throw new Error('must implement');
    },
    /** @type {(id: string) => void} */
    dismiss: (_id) => {
        throw new Error('must implement');
    },
    /** @type {(id: string) => void} */
    action: (_id) => {
        throw new Error('must implement');
    },
});

export const NextStepsDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A data provider that will use `NextStepsService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function NextStepsProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    // const [state, dispatch] = useReducer(withLog('NextStepsProvider', reducer), initial)
    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `NextStepsService` for the lifespan of this component.
    const service = useService();

    // get initial data
    useInitialDataAndConfig({ dispatch, service });

    // subscribe to data updates
    useDataSubscription({ dispatch, service });

    // subscribe to config updates
    useConfigSubscription({ dispatch, service });

    // expose a fn for sync toggling
    const toggle = useCallback(() => {
        service.current?.toggleExpansion();
    }, [service]);

    /** @type {(id: string) => void} */
    const action = useCallback(
        (id) => {
            service.current?.action(id);
        },
        [service],
    );

    /** @type {(id: string) => void} */
    const dismiss = useCallback(
        (id) => {
            service.current?.dismiss(id);
        },
        [service],
    );

    return (
        <NextStepsContext.Provider value={{ state, toggle, action, dismiss }}>
            <NextStepsDispatchContext.Provider value={dispatch}>{props.children}</NextStepsDispatchContext.Provider>
        </NextStepsContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<NextStepsService>}
 */
export function useService() {
    const service = useRef(/** @type {NextStepsService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new NextStepsService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}
