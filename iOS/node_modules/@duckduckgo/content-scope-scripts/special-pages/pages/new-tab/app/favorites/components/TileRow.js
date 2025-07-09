import styles from './Favorites.module.css';
import { Placeholder, PlusIconMemo, Tile } from './Tile.js';
import { h } from 'preact';
import { memo } from 'preact/compat';
import { FavoritesThemeContext, ROW_CAPACITY } from './Favorites.js';
import { useContext } from 'preact/hooks';
import { useFaviconRefreshedCount } from './FavoritesProvider.js';

/**
 * @typedef {import('../../../types/new-tab.js').Favorite} Favorite
 */

export const TileRow = memo(
    /**
     * Represents a row of tiles with optional placeholders to fill empty spaces in the first row.
     * @param {object} props - An object containing parameters for the TileRow_ function.
     * @param {number} props.topOffset - The top offset position of the row (relative to the container)
     * @param {Favorite[]} props.items - An array of favorites to be displayed as tiles in the row.
     * @param {Document['visibilityState']} props.visibility - whether this item is actually visible
     * @param {() => void} props.add - A function to be called when a new item is added to the row.
     */
    function TileRow({ topOffset, items, add, visibility }) {
        const fillers = ROW_CAPACITY - items.length;
        const { theme, animateItems } = useContext(FavoritesThemeContext);
        const count = useFaviconRefreshedCount();
        return (
            <ul className={styles.gridRow} style={{ transform: `translateY(${topOffset}px)` }}>
                {items.map((item, index) => {
                    return (
                        <Tile
                            url={item.url}
                            etldPlusOne={item.etldPlusOne}
                            faviconSrc={item.favicon?.src}
                            faviconMax={item.favicon?.maxAvailableSize}
                            title={item.title}
                            key={item.id + item.favicon?.src + item.favicon?.maxAvailableSize + visibility + count.value}
                            id={item.id}
                            index={index}
                            visibility={visibility}
                            theme={theme}
                            animateItems={animateItems.value}
                        />
                    );
                })}
                {fillers > 0 &&
                    Array.from({ length: fillers }).map((_, fillerIndex) => {
                        // first is always the + (plus) button
                        if (fillerIndex === 0) {
                            return <PlusIconMemo key={`placeholder-plus-${items.length}`} onClick={add} />;
                        }

                        // for all the rest, just fill the row with dotted outlines
                        return <Placeholder key={`placeholder-${items.length}`} />;
                    })}
            </ul>
        );
    },
);
