import { createContext, h } from 'preact';
import { useCallback, useEffect, useReducer, useRef } from 'preact/hooks';
import { useInitialSetupData, useMessaging } from '../types.js';
import { UpdateNotificationService } from './update-notification.service.js';
import { reducer, useDataSubscription } from '../service.hooks.js';

/**
 * @typedef {import('../../types/new-tab.js').UpdateNotificationData} UpdateNotificationData
 * @typedef {import('../service.hooks.js').State<UpdateNotificationData, undefined>} State
 * @typedef {import('../service.hooks.js').Events<UpdateNotificationData, undefined>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const UpdateNotificationContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
    /** @type {() => void} */
    dismiss: () => {
        throw new Error('must implement dismiss');
    },
});

export const UpdateNotificationDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A data provider that will use `RMFService` to fetch data, subscribe
 * to updates and modify state.
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function UpdateNotificationProvider(props) {
    const { updateNotification } = useInitialSetupData();
    if (updateNotification === null) {
        return null;
    }
    return <UpdateNotificationWithInitial updateNotification={updateNotification}>{props.children}</UpdateNotificationWithInitial>;
}

/**
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {UpdateNotificationData} props.updateNotification
 */
function UpdateNotificationWithInitial({ updateNotification, children }) {
    const initial = /** @type {State} */ ({
        status: 'ready',
        data: updateNotification,
        config: undefined,
    });

    // const [state, dispatch] = useReducer(withLog('RMFProvider', reducer), initial)
    const [state, dispatch] = useReducer(reducer, initial);

    // create an instance of `RMFService` for the lifespan of this component.
    const service = useService(updateNotification);

    // subscribe to data updates
    useDataSubscription({ dispatch, service });

    const dismiss = useCallback(() => {
        service.current?.dismiss();
    }, [service]);

    return (
        <UpdateNotificationContext.Provider value={{ state, dismiss }}>
            <UpdateNotificationDispatchContext.Provider value={dispatch}>{children}</UpdateNotificationDispatchContext.Provider>
        </UpdateNotificationContext.Provider>
    );
}

/**
 * @param {UpdateNotificationData} initial
 * @return {import("preact").RefObject<UpdateNotificationService>}
 */
export function useService(initial) {
    const service = useRef(/** @type {UpdateNotificationService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new UpdateNotificationService(ntp, initial);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp, initial]);
    return service;
}
