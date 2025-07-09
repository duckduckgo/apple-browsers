import { createContext, h } from 'preact';
import { useCallback, useContext, useEffect } from 'preact/hooks';
import { eventToTarget } from '../utils.js';
import { useBatchedActivityApi, usePlatformName } from '../settings.provider.js';
import { ACTION_ADD_FAVORITE, ACTION_REMOVE, ACTION_REMOVE_FAVORITE } from './constants.js';
import { batch, signal, useSignal } from '@preact/signals';
import { DDG_DEFAULT_ICON_SIZE } from '../favorites/constants.js';
import { ActivityContext, ActivityServiceContext } from './ActivityProvider.js';
import { ActivityInteractionsContext } from '../burning/ActivityInteractionsContext.js';
import { ACTION_BURN } from '../burning/BurnProvider.js';

/**
 * @typedef {import('../../types/new-tab.js').ActivityData} ActivityData
 * @typedef {import('../../types/new-tab').TrackingStatus} TrackingStatus
 * @typedef {import('../../types/new-tab').HistoryEntry} HistoryEntry
 * @typedef {import('../../types/new-tab').DomainActivity} DomainActivity
 * @typedef {import('../service.hooks.js').State<import("./batched-activity.service.js").Incoming, null>} State
 * @typedef {import('../service.hooks.js').Events<ActivityData, null>} Events
 */

/**
 * @typedef Item
 * @property {string} props.title
 * @property {string} props.url
 * @property {string|null|undefined} props.favoriteSrc
 * @property {number} props.faviconMax
 * @property {string} props.etldPlusOne
 * @property {boolean} props.trackersFound
 */

/**
 * @typedef NormalizedActivity
 * @property {Record<string, Item>} items
 * @property {Record<string, HistoryEntry[]>} history
 * @property {Record<string, TrackingStatus>} trackingStatus
 * @property {Record<string, boolean>} favorites
 * @property {string[]} urls
 * @property {number} totalTrackers
 */

/**
 * @param {NormalizedActivity} prev
 * @param {import("./batched-activity.service.js").Incoming} incoming
 * @return {NormalizedActivity}
 */
export function normalizeData(prev, incoming) {
    /** @type {NormalizedActivity} */
    const output = {
        favorites: {},
        items: {},
        history: {},
        trackingStatus: {},
        urls: [],
        totalTrackers: incoming.totalTrackers,
    };

    if (shallowDiffers(prev.urls, incoming.urls)) {
        output.urls = [...incoming.urls];
    } else {
        output.urls = prev.urls;
    }

    for (const item of incoming.activity) {
        const id = item.url;

        output.favorites[id] = item.favorite;

        /** @type {Item} */
        const next = {
            etldPlusOne: item.etldPlusOne,
            title: item.title,
            url: id,
            faviconMax: item.favicon?.maxAvailableSize ?? DDG_DEFAULT_ICON_SIZE,
            favoriteSrc: item.favicon?.src,
            trackersFound: item.trackersFound,
        };
        const differs = shallowDiffers(next, prev.items[id] || {});
        output.items[id] = differs ? next : prev.items[id] || {};

        const historyDiff = shallowDiffers(item.history, prev.history[id] || []);
        output.history[id] = historyDiff ? [...item.history] : prev.history[id] || [];

        const prevItem = prev.trackingStatus[id] || {
            totalCount: 0,
            trackerCompanies: [],
        };
        const trackersDiffer = shallowDiffers(item.trackingStatus.trackerCompanies, prevItem.trackerCompanies);
        if (prevItem.totalCount !== item.trackingStatus.totalCount || trackersDiffer) {
            const next = {
                totalCount: item.trackingStatus.totalCount,
                trackerCompanies: [...item.trackingStatus.trackerCompanies],
            };
            output.trackingStatus[id] = next;
        } else {
            output.trackingStatus[id] = prevItem;
        }
    }
    return output;
}

/**
 * @param {string[]} prev
 * @param {string[]} data
 * @return {string[]}
 */
function normalizeKeys(prev, data) {
    const next = shallowDiffers(prev, data) ? [...data] : prev;
    return next;
}

/**
 * Check if two objects have a different shape
 * @param {object} a
 * @param {object} b
 * @returns {boolean}
 */
export function shallowDiffers(a, b) {
    for (const i in a) if (i !== '__source' && !(i in b)) return true;
    for (const i in b) if (i !== '__source' && a[i] !== b[i]) return true;
    return false;
}

export const NormalizedDataContext = createContext({
    activity: signal(/** @type {NormalizedActivity} */ ({})),
    keys: signal(/** @type {string[]} */ ([])),
});

export function SignalStateProvider({ children }) {
    const { state } = useContext(ActivityContext);
    const batched = useBatchedActivityApi();
    const platformName = usePlatformName();
    const service = /** @type {import("./batched-activity.service.js").BatchedActivityService} */ (useContext(ActivityServiceContext));
    if (state.status !== 'ready') throw new Error('must have ready status here');
    if (!service) throw new Error('must have service here');

    /**
     * @param {MouseEvent} event
     */
    function didClick_(event) {
        const target = /** @type {HTMLElement|null} */ (event.target);
        if (!target) return;
        if (!service) return;
        const anchor = /** @type {HTMLAnchorElement|null} */ (target.closest('a[href][data-url]'));
        const button = /** @type {HTMLButtonElement|null} */ (target.closest('button[value][data-action]'));
        if (anchor) {
            const url = anchor.dataset.url;
            if (!url) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            const openTarget = eventToTarget(event, platformName);
            service.openUrl(url, openTarget);
        } else if (button) {
            event.preventDefault();
            event.stopImmediatePropagation();

            const action = button.dataset.action;
            const value = button.value;

            if (!action) return console.warn('expected clicked button to have data-action="<value>"');
            if (typeof value !== 'string') return console.warn('expected clicked button to have a value');

            if (action === ACTION_ADD_FAVORITE) {
                service.addFavorite(button.value);
            } else if (action === ACTION_REMOVE_FAVORITE) {
                service.removeFavorite(button.value);
            } else if (action === ACTION_BURN) {
                // burning will be captured elsewhere
                console.warn('Should not get here... Burning should be captured elsewhere?');
            } else if (action === ACTION_REMOVE) {
                service.remove(button.value);
            } else {
                console.warn('unhandled action:', action);
            }
        }
    }

    const didClick = useCallback(didClick_, [service, batched]);
    const firstUrls = state.data.activity.map((x) => x.url);
    const keys = useSignal(normalizeKeys([], firstUrls));

    const activity = useSignal(
        normalizeData(
            {
                items: {},
                history: {},
                trackingStatus: {},
                favorites: {},
                urls: [],
                totalTrackers: 0,
            },
            { activity: state.data.activity, urls: state.data.urls, totalTrackers: state.data.totalTrackers },
        ),
    );

    /**
     * @param {string[]} nextVisibleRange
     */
    function setVisibleRange(nextVisibleRange) {
        keys.value = normalizeKeys(keys.value, nextVisibleRange);
    }

    function fillHoles() {
        const visible = keys.value;
        const data = Object.keys(activity.value.items);
        const missing = visible.filter((x) => !data.includes(x));
        service.next(missing);
    }

    function showNextChunk() {
        if (service.isFetchingNext) return;
        if (!batched) return;
        const visibleLength = keys.value.length;
        const end = visibleLength + service.CHUNK_SIZE;
        const nextVisibleRange = activity.value.urls.slice(0, end);
        setVisibleRange(nextVisibleRange);
        fillHoles();
    }

    useEffect(() => {
        if (!service) return console.warn('could not access service');
        const src = /** @type {import("./batched-activity.service.js").BatchedActivityService} */ (service);
        const unsub = src.onData((evt) => {
            batch(() => {
                activity.value = normalizeData(activity.value, {
                    activity: evt.data.activity,
                    urls: evt.data.urls,
                    totalTrackers: evt.data.totalTrackers,
                });
                const visible = keys.value;
                const all = activity.value.urls;

                // prettier-ignore
                const nextVisibleRange = batched
                    ? all.slice(0, Math.max(service.INITIAL, Math.max(service.INITIAL, visible.length)))
                    : all

                setVisibleRange(nextVisibleRange);
                fillHoles();
            });
        });

        return () => {
            unsub();
        };
    }, [service, batched, activity, keys]);

    useEffect(() => {
        window.addEventListener('activity.next', showNextChunk);
        return () => {
            window.removeEventListener('activity.next', showNextChunk);
        };
    }, []);

    useEffect(() => {
        const handler = () => {
            if (document.visibilityState === 'visible') {
                if (batched) {
                    const visible = keys.value;
                    service.triggerDataFetch(visible);
                } else {
                    service.triggerDataFetch();
                }
            }
        };

        // eslint-disable-next-line no-labels,no-unused-labels
        $INTEGRATION: (() => {
            // export the event in tests
            if (window.__playwright_01) {
                /** @type {any} */ (window).__trigger_document_visibilty__ = handler;
            }
        })();

        document.addEventListener('visibilitychange', handler);
        return () => {
            document.removeEventListener('visibilitychange', handler);
        };
    }, [batched]);

    return (
        <NormalizedDataContext.Provider value={{ activity, keys }}>
            <ActivityInteractionsContext.Provider value={{ didClick }}>{children}</ActivityInteractionsContext.Provider>
        </NormalizedDataContext.Provider>
    );
}
