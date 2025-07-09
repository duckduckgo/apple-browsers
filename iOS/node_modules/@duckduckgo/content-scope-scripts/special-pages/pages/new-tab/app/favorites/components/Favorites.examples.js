import { h } from 'preact';
import { favorites } from '../mocks/favorites.data.js';
import { MockFavoritesProvider } from '../mocks/MockFavoritesProvider.js';
import { FavoritesConsumer } from './FavoritesCustomized.js';

/** @type {Record<string, {factory: () => import("preact").ComponentChild}>} */

export const favoritesExamples = {
    'favorites.dnd': {
        factory: () => (
            <MockFavoritesProvider data={favorites.many}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.few.7': {
        factory: () => (
            <MockFavoritesProvider data={{ favorites: favorites.many.favorites.slice(0, 7) }}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.few.7.no-animation': {
        factory: () => (
            <MockFavoritesProvider
                data={{ favorites: favorites.many.favorites.slice(0, 7) }}
                config={{ expansion: 'expanded', animation: { kind: 'none' } }}
            >
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.few.6': {
        factory: () => (
            <MockFavoritesProvider data={{ favorites: favorites.many.favorites.slice(0, 6) }}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.few.12': {
        factory: () => (
            <MockFavoritesProvider data={{ favorites: favorites.many.favorites.slice(0, 12) }}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.multi': {
        factory: () => (
            <div>
                <MockFavoritesProvider data={favorites.many}>
                    <FavoritesConsumer />
                </MockFavoritesProvider>
                <br />
                <MockFavoritesProvider data={favorites.single}>
                    <FavoritesConsumer />
                </MockFavoritesProvider>
                <br />
                <MockFavoritesProvider data={favorites.none}>
                    <FavoritesConsumer />
                </MockFavoritesProvider>
            </div>
        ),
    },
    'favorites.single': {
        factory: () => (
            <MockFavoritesProvider data={favorites.single}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
    'favorites.none': {
        factory: () => (
            <MockFavoritesProvider data={favorites.none}>
                <FavoritesConsumer />
            </MockFavoritesProvider>
        ),
    },
};
