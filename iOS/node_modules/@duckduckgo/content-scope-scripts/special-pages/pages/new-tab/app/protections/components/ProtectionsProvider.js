import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../../types.js';
import { reducer, useConfigSubscription, useInitialDataAndConfig } from '../../service.hooks.js';
import { ProtectionsService } from '../protections.service.js';
import { useSignal, useSignalEffect } from '@preact/signals';

/**
 * @typedef {import('../../../types/new-tab.js').ProtectionsData} ProtectionsData
 * @typedef {import('../../../types/new-tab.js').ProtectionsConfig} ProtectionsConfig
 * @typedef {import('../../service.hooks.js').State<ProtectionsData, ProtectionsConfig>} State
 * @typedef {import('../../service.hooks.js').Events<ProtectionsData, ProtectionsConfig>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const ProtectionsContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {() => void} */
    toggle: () => {
        throw new Error('must implement');
    },
    /** @type {(feed: ProtectionsConfig['feed']) => void} */
    setFeed: (_feed) => {
        throw new Error('must implement');
    },
});

export const ProtectionsServiceContext = createContext(/** @type {ProtectionsService|null} */ ({}));

/**
 * A data provider that will use `ProtectionsService` to fetch initial data only
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function ProtectionsProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `ProtectionsService` for the lifespan of this component.
    const service = useService();

    // get initial data
    useInitialDataAndConfig({ dispatch, service });

    // subscribe to config updates
    useConfigSubscription({ dispatch, service });

    // expose a fn for sync toggling
    const toggle = useCallback(() => {
        service.current?.toggleExpansion();
    }, [service]);

    /** @type {(feed: ProtectionsConfig['feed']) => void} */
    const setFeed = useCallback(
        (feed) => {
            service.current?.setFeed(feed);
        },
        [service],
    );

    return (
        <ProtectionsContext.Provider value={{ state, toggle, setFeed }}>
            <ProtectionsServiceContext.Provider value={service.current}>{props.children}</ProtectionsServiceContext.Provider>
        </ProtectionsContext.Provider>
    );
}

/**
 * @return {import("preact").RefObject<ProtectionsService>}
 */
export function useService() {
    const service = useRef(/** @type {ProtectionsService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new ProtectionsService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}

/**
 * @param {number} initial
 * @return {import("@preact/signals").Signal<number>}
 */
export function useBlockedCount(initial) {
    const service = useService();
    const signal = useSignal(initial);
    useSignalEffect(() => {
        return service.current?.onData((evt) => {
            signal.value = evt.data.totalCount;
        });
    });
    return signal;
}
