import { h } from 'preact';
import { useContext } from 'preact/hooks';

import { useTelemetry, useTypedTranslationWith } from '../../types.js';
import { useVisibility } from '../../widget-list/widget-config.provider.js';
import { useCustomizer } from '../../customizer/components/CustomizerMenu.js';

import { FavoritesContext, FavoritesProvider } from './FavoritesProvider.js';
import { PragmaticDND } from './PragmaticDND.js';
import { FavoritesMemo } from './Favorites.js';
import { viewTransition } from '../../utils.js';
import { CustomizerContext } from '../../customizer/CustomizerProvider.js';

/**
 * @typedef {import('../../../types/new-tab.ts').Favorite} Favorite
 * Component that consumes FavoritesContext for displaying favorites list.
 */
export function FavoritesConsumer() {
    const { state, toggle, favoritesDidReOrder, openContextMenu, openFavorite, add } = useContext(FavoritesContext);
    const telemetry = useTelemetry();
    const { data: backgroundData } = useContext(CustomizerContext);

    /**
     * Checks if view transitions are supported and initiates reordering of favorites accordingly.
     *
     * @param {{id: string; list: Favorite[], fromIndex: number, targetIndex: number}} data
     */
    function didReorder(data) {
        const background = backgroundData.value.background;
        const supportsViewTransitions = state.config?.animation?.kind === 'view-transitions' && background.kind !== 'userImage';

        if (supportsViewTransitions) {
            viewTransition(() => {
                favoritesDidReOrder(data);
            });
        } else {
            favoritesDidReOrder(data);
        }
    }

    if (state.status === 'ready') {
        telemetry.measureFromPageLoad('favorites-will-render', 'time to favorites');
        return (
            <PragmaticDND items={state.data.favorites} itemsDidReOrder={didReorder}>
                <FavoritesMemo
                    favorites={state.data.favorites}
                    expansion={state.config.expansion}
                    canAnimateItems={state.config?.animation?.kind === 'view-transitions'}
                    openContextMenu={openContextMenu}
                    openFavorite={openFavorite}
                    add={add}
                    toggle={toggle}
                />
            </PragmaticDND>
        );
    }
    return null;
}

/**
 * Render the favorites widget, with integration into the page customizer
 */
export function FavoritesCustomized() {
    const { t } = useTypedTranslationWith(/** @type {import("../strings.json")} */ ({}));
    const { id, visibility, toggle, index } = useVisibility();

    // register with the visibility menu
    const title = t('favorites_menu_title');
    useCustomizer({ title, id, icon: 'star', toggle, visibility: visibility.value, index });

    if (visibility.value === 'hidden') {
        return null;
    }
    return (
        <FavoritesProvider>
            <FavoritesConsumer />
        </FavoritesProvider>
    );
}
