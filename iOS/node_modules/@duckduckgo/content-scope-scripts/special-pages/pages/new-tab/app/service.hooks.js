/**
 * @template Data, Config
 * @typedef {{ kind: 'initial-data'; data: Data, config: Config }
 *         | { kind: 'data'; data: Data }
 *         | { kind: 'config'; config: Config; }
 *         | { kind: 'load-initial'; }
 *         | { kind: 'error'; error: string }
 *         | { kind: 'clear'; }
 * } Events
 *
 */

/**
 * @typedef {'entering' | 'exiting' | 'entered'} Ui
 * @typedef {import('./service.js').InvocationSource} InvocationSource
 */

/**
 * @template Data, Config
 * @typedef {{status: 'idle'; data: null, config: null}
 *         | {status: 'pending-initial'; data: null, config: null}
 *         | {status: 'ready'; data: Data; config: Config}
 * } State
 */

import { useEffect } from 'preact/hooks';
import { useMessaging } from './types.js';

/**
 * @template D
 * @template C
 * @param {State<D, C>} state
 * @param {Events<D, C>} event
 */
export function reducer(state, event) {
    switch (state.status) {
        case 'idle': {
            switch (event.kind) {
                case 'load-initial': {
                    return { ...state, status: /** @type {const} */ ('pending-initial') };
                }
                default:
                    return state;
            }
        }
        case 'pending-initial': {
            switch (event.kind) {
                case 'initial-data': {
                    return {
                        ...state,
                        status: /** @type {const} */ ('ready'),
                        data: event.data,
                        config: event.config,
                    };
                }
                case 'error': {
                    console.error('error with initial data', event.error);
                    return state;
                }
                default:
                    return state;
            }
        }
        case 'ready': {
            switch (event.kind) {
                case 'config': {
                    return { ...state, config: event.config };
                }
                case 'data': {
                    return { ...state, data: event.data };
                }
                case 'clear': {
                    return { ...state, effect: null };
                }
                default:
                    return state;
            }
        }
        default:
            return state;
    }
}

/**
 * @template D,C
 * @param {object} params
 * @param {import("preact/hooks").Dispatch<any>} params.dispatch
 * @param {import("preact").RefObject<{
 *   getInitial: () => Promise<{data: D, config: C}>;
 *   destroy: () => void;
 *   name: () => string;
 * }>} params.service
 */
export function useInitialDataAndConfig({ dispatch, service }) {
    const messaging = useMessaging();
    useEffect(() => {
        if (!service.current) return console.warn('missing service');
        const currentService = service.current;
        async function init() {
            const { data, config } = await currentService.getInitial();
            if (data || config) {
                dispatch({ kind: 'initial-data', data, config });
            } else {
                dispatch({ kind: 'error', error: 'missing data from getInitial' });
            }
        }

        dispatch({ kind: 'load-initial' });

        // eslint-disable-next-line promise/prefer-await-to-then
        init().catch((e) => {
            console.error('uncaught error', e);
            dispatch({ kind: 'error', error: e });
            messaging.reportPageException({ message: `${currentService.name()}: failed to fetch initial data+config: ` + e.message });
        });

        return () => {
            currentService.destroy();
        };
    }, [messaging]);
}

/**
 * @template D
 * @param {object} params
 * @param {import("preact/hooks").Dispatch<any>} params.dispatch
 * @param {import("preact").RefObject<{
 *   getInitial: () => Promise<D>;
 *   destroy: () => void;
 *   name: () => string;
 * }>} params.service
 */
export function useInitialData({ dispatch, service }) {
    const messaging = useMessaging();
    useEffect(() => {
        if (!service.current) return console.warn('missing service');
        const currentService = service.current;
        async function init() {
            const data = await currentService.getInitial();
            if (data) {
                dispatch({ kind: 'initial-data', data });
            } else {
                dispatch({ kind: 'error', error: 'missing data from getInitial' });
            }
        }

        dispatch({ kind: 'load-initial' });

        // eslint-disable-next-line promise/prefer-await-to-then
        init().catch((e) => {
            console.error('uncaught error', e);
            dispatch({ kind: 'error', error: e });
            messaging.reportPageException({ message: `${currentService.name()}: failed to fetch initial data: ` + e.message });
        });

        return () => {
            currentService.destroy();
        };
    }, []);
}

/**
 * Subscribe to data updates
 * @template Data
 * @param {object} params
 * @param {import("preact/hooks").Dispatch<Events<Data, any>>} params.dispatch
 * @param {import("preact").RefObject<{
 *     onData: (cb: (d: {data:Data})=>void) => () => void
 * }>} params.service
 */
export function useDataSubscription({ dispatch, service }) {
    useEffect(() => {
        if (!service.current) return console.warn('could not access service');

        const unsub = service.current.onData((evt) => {
            dispatch({ kind: 'data', data: evt.data });
        });
        return () => {
            unsub();
        };
    }, [service, dispatch]);
}

/**
 * Subscribe to config updates
 * @template Config
 * @param {object} params
 * @param {import("preact/hooks").Dispatch<Events<any, Config>>} params.dispatch
 * @param {import("preact").RefObject<{
 *    onConfig: (cb: (event: { data: Config, source: InvocationSource}) => void) => () => void;
 * }>} params.service
 */
export function useConfigSubscription({ dispatch, service }) {
    useEffect(() => {
        if (!service.current) return console.warn('could not access service');
        const unsub2 = service.current.onConfig((data) => {
            dispatch({ kind: 'config', config: data.data });
        });
        return () => {
            unsub2();
        };
    }, [service]);
}
