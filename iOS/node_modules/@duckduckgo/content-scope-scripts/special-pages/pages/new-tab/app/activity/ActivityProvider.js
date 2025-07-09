import { createContext, h } from 'preact';
import { useEffect, useReducer, useRef } from 'preact/hooks';
import { useMessaging } from '../types.js';
import { reducer, useInitialData } from '../service.hooks.js';
import { useBatchedActivityApi } from '../settings.provider.js';
import { BatchedActivityService } from './batched-activity.service.js';

/**
 * @typedef {import('../../types/new-tab.js').ActivityData} ActivityData
 * @typedef {import('../../types/new-tab').TrackingStatus} TrackingStatus
 * @typedef {import('../../types/new-tab').HistoryEntry} HistoryEntry
 * @typedef {import('../../types/new-tab').DomainActivity} DomainActivity
 * @typedef {import('../service.hooks.js').State<import("./batched-activity.service.js").Incoming, null>} State
 * @typedef {import('../service.hooks.js').Events<ActivityData, null>} Events
 */

/**
 * These are the values exposed to consumers.
 */
export const ActivityContext = createContext({
    /** @type {State} */
    state: { status: 'idle', data: null, config: null },
});

export const ActivityServiceContext = createContext(/** @type {BatchedActivityService|null} */ ({}));

/**
 * A data provider that will use `ActivityService` to fetch initial data only
 *
 * @param {Object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function ActivityProvider(props) {
    const initial = /** @type {State} */ ({
        status: 'idle',
        data: null,
        config: null,
    });

    const [state, dispatch] = useReducer(reducer, initial);
    const batched = useBatchedActivityApi();

    // create an instance of `ActivityService` for the lifespan of this component.
    const service = useService(batched);

    // get initial data
    useInitialData({ dispatch, service });

    return (
        <ActivityContext.Provider value={{ state }}>
            <ActivityServiceContext.Provider value={service.current}>{props.children}</ActivityServiceContext.Provider>
        </ActivityContext.Provider>
    );
}

/**
 * @param {boolean} useBatched
 * @return {import("preact").RefObject<BatchedActivityService>}
 */
export function useService(useBatched) {
    const service = useRef(/** @type {BatchedActivityService|null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new BatchedActivityService(ntp, useBatched);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp, useBatched]);
    return service;
}
