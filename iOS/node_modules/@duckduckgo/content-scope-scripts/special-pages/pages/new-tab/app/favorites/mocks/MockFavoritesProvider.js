import { h } from 'preact';
import { FavoritesContext, FavoritesDispatchContext } from '../components/FavoritesProvider.js';
import { useCallback, useReducer, useState } from 'preact/hooks';
import { useEnv } from '../../../../../shared/components/EnvironmentProvider.js';
import { favorites } from './favorites.data.js';
import { reducer } from '../../service.hooks.js';

/**
 * @typedef {import('../../../types/new-tab').Favorite} Favorite
 * @typedef {import('../../../types/new-tab').FavoritesData} FavoritesData
 * @typedef {import('../../../types/new-tab').FavoritesConfig} FavoritesConfig
 * @typedef {import('../../service.hooks.js').State<FavoritesData, FavoritesConfig>} State
 * @typedef {import('../../service.hooks.js').Events<FavoritesData, FavoritesConfig>} Events
 */

/** @type {FavoritesConfig} */
const DEFAULT_CONFIG = {
    expansion: 'expanded',
};

/**
 * @param {object} props
 * @param {import("preact").ComponentChild} props.children
 * @param {FavoritesData} [props.data]
 * @param {FavoritesConfig} [props.config]
 */
export function MockFavoritesProvider({ data = favorites.many, config = DEFAULT_CONFIG, children }) {
    const { isReducedMotion } = useEnv();

    const initial = /** @type {State} */ ({
        status: 'ready',
        data,
        config,
    });

    const [et] = useState(() => new EventTarget());

    /** @type {[State, import('preact/hooks').Dispatch<Events>]} */
    const [state, dispatch] = useReducer(reducer, initial);

    const toggle = useCallback(() => {
        if (state.status !== 'ready') return;
        const next =
            state.config.expansion === 'expanded'
                ? /** @type {const} */ ({ ...state.config, expansion: 'collapsed' })
                : /** @type {const} */ ({ ...state.config, expansion: 'expanded' });

        dispatch({ kind: 'config', config: next });
        et.dispatchEvent(new CustomEvent('state-update', { detail: next }));
    }, [state.status, state.config?.expansion, isReducedMotion]);

    /** @type {import('../components/FavoritesProvider.js').ReorderFn<Favorite>} */
    const favoritesDidReOrder = useCallback(({ list }) => {
        dispatch({ kind: 'data', data: { favorites: list } });
    }, []);

    const openContextMenu = (...args) => {
        console.log('noop openContextMenu', ...args);
        /* no-op */
    };

    const openFavorite = (...args) => {
        console.log('noop openFavorite', ...args);
        /* no-op */
    };

    const add = (...args) => {
        /* no-op */
        console.log('noop add', ...args);
    };

    const onConfigChanged = useCallback(
        (cb) => {
            et.addEventListener('state-update', (/** @type {CustomEvent<any>} */ e) => {
                cb(e.detail);
            });
        },
        [et],
    );

    return (
        <FavoritesContext.Provider value={{ state, toggle, favoritesDidReOrder, openContextMenu, openFavorite, add, onConfigChanged }}>
            <FavoritesDispatchContext.Provider value={dispatch}>{children}</FavoritesDispatchContext.Provider>
        </FavoritesContext.Provider>
    );
}
