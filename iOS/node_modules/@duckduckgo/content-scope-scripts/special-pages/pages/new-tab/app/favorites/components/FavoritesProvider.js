import { createContext, h } from 'preact';
import { useCallback, useContext, useEffect, useReducer, useRef } from 'preact/hooks';

import { FavoritesService } from '../favorites.service.js';
import { useMessaging } from '../../types.js';
import { reducer, useConfigSubscription, useDataSubscription, useInitialDataAndConfig } from '../../service.hooks.js';
import { signal, useSignal } from '@preact/signals';

/**
 * @typedef {import('../../../types/new-tab.ts').Favorite} Favorite
 * @typedef {import('../../../types/new-tab.ts').FavoritesData} FavoritesData
 * @typedef {import('../../../types/new-tab.ts').FavoritesConfig} FavoritesConfig
 * @typedef {import('../../../types/new-tab.ts').FavoritesOpenAction['target']} OpenTarget
 * @typedef {import('../../service.hooks.js').State<FavoritesData, FavoritesConfig>} State
 * @typedef {import('../../service.hooks.js').Events<FavoritesData, FavoritesConfig>} Events
 * @typedef {{id: string; url: string}} BaseFavoriteType
 */

/**
 * @template {BaseFavoriteType} ItemType - allow any type that extends BaseFavoriteType
 * @typedef {(params: { list: ItemType[], id: string, fromIndex: number, targetIndex: number }) => void} ReorderFn
 */

/**
 * These are the values exposed to consumers.
 */
export const FavoritesContext = createContext({
    /** @type {import('../../service.hooks.js').State<FavoritesData, FavoritesConfig>} */
    state: { status: 'idle', data: null, config: null },
    /** @type {() => void} */
    toggle: () => {
        throw new Error('must implement');
    },
    /** @type {ReorderFn<Favorite>} */
    favoritesDidReOrder: (_args) => {
        throw new Error('must implement');
    },
    /** @type {(id: string) => void} */
    openContextMenu: (_id) => {
        throw new Error('must implement');
    },
    /** @type {(id: string, url: string, target: OpenTarget) => void} */
    openFavorite: (_id, _url, _target) => {
        throw new Error('must implement');
    },
    /** @type {() => void} */
    add: () => {
        throw new Error('must implement add');
    },
    /** @type {(cb: (data: FavoritesConfig) => void) => void} */
    onConfigChanged: (_cb) => {
        /** noop */
    },
});

export const FavoritesDispatchContext = createContext(/** @type {import("preact/hooks").Dispatch<Events>} */ ({}));

/**
 * A simple counter than can be used to invalidate a tree. For example, to force the browser
 * to re-fetch icons that previously gave a 404 response
 */
export const FaviconsRefreshedCount = createContext(signal(0));

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 */
export function FavoritesProvider({ children }) {
    const initial = /** @type {State} */ ({
        status: /** @type {const} */ ('idle'),
        data: null,
        config: null,
    });

    const [state, dispatch] = useReducer(reducer, initial);

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

    /** @type {ReorderFn<Favorite>} */
    const favoritesDidReOrder = useCallback(
        ({ list, id, fromIndex, targetIndex }) => {
            if (!service.current) return;
            service.current.setFavoritesOrder({ favorites: list }, id, fromIndex, targetIndex);
        },
        [service],
    );

    /** @type {(id: string) => void} */
    const openContextMenu = useCallback(
        (id) => {
            if (!service.current) return;
            service.current.openContextMenu(id);
        },
        [service],
    );

    /** @type {(id: string, url: string, target: OpenTarget) => void} */
    const openFavorite = useCallback(
        (id, url, target) => {
            if (!service.current) return;
            service.current.openFavorite(id, url, target);
        },
        [service],
    );

    /** @type {() => void} */
    const add = useCallback(() => {
        if (!service.current) return;
        service.current.add();
    }, [service]);

    /** @type {(cb: (data: FavoritesConfig) => void) => void} */
    const onConfigChanged = useCallback(
        (cb) => {
            if (!service.current) return;
            return service.current.onConfig((event) => {
                cb(event.data);
            });
        },
        [service],
    );

    const faviconsRefreshedCount = useSignal(0);
    useEffect(() => {
        if (!service.current) return;
        return service.current.onFaviconsRefreshed(() => {
            faviconsRefreshedCount.value = faviconsRefreshedCount.value += 1;
        });
    }, []);

    return (
        <FavoritesContext.Provider value={{ state, toggle, favoritesDidReOrder, openFavorite, openContextMenu, add, onConfigChanged }}>
            <FaviconsRefreshedCount.Provider value={faviconsRefreshedCount}>
                <FavoritesDispatchContext.Provider value={dispatch}>{children}</FavoritesDispatchContext.Provider>
            </FaviconsRefreshedCount.Provider>
        </FavoritesContext.Provider>
    );
}

export function useService() {
    const service = useRef(/** @type {FavoritesService | null} */ (null));
    const ntp = useMessaging();
    useEffect(() => {
        const stats = new FavoritesService(ntp);
        service.current = stats;
        return () => {
            stats.destroy();
        };
    }, [ntp]);
    return service;
}

export function useFaviconRefreshedCount() {
    return useContext(FaviconsRefreshedCount);
}
