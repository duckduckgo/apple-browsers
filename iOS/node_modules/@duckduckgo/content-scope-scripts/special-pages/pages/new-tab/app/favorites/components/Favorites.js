import { createContext, Fragment, h } from 'preact';
import { useContext, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from 'preact/hooks';
import { memo } from 'preact/compat';

import styles from './Favorites.module.css';
import { ShowHideBar, ShowHideButtonPill } from '../../components/ShowHideButton.jsx';
import { useTypedTranslationWith } from '../../types.js';
import { usePlatformName } from '../../settings.provider.js';
import { useDropzoneSafeArea } from '../../dropzone.js';
import { TileRow } from './TileRow.js';
import { FavoritesContext } from './FavoritesProvider.js';
import { CustomizerContext, CustomizerThemesContext } from '../../customizer/CustomizerProvider.js';
import { signal, useComputed } from '@preact/signals';
import { eventToTarget, useOnMiddleClick } from '../../utils.js';
import { useDocumentVisibility } from '../../../../../shared/components/DocumentVisibility';

/**
 * @typedef {import('../../../types/new-tab.js').Expansion} Expansion
 * @typedef {import('../../../types/new-tab.js').Favorite} Favorite
 * @typedef {import('../../../types/new-tab.js').FavoritesOpenAction['target']} OpenTarget
 */
export const FavoritesMemo = memo(Favorites);
export const ROW_CAPACITY = 6;
/**
 * Note: These values MUST match exactly what's defined in the CSS.
 */
const ITEM_HEIGHT = 96;
const ROW_GAP = 8;
export const FavoritesThemeContext = createContext({
    theme: /** @type {"light"|"dark"} */ ('light'),
    animateItems: signal(false),
});

/**
 * Favorites Grid.
 *
 * @param {object} props
 * @param {Favorite[]} props.favorites
 * @param {Expansion} props.expansion
 * @param {() => void} props.toggle
 * @param {(id: string) => void} props.openContextMenu
 * @param {(id: string, url: string, target: OpenTarget) => void} props.openFavorite
 * @param {() => void} props.add
 * @param {boolean} props.canAnimateItems
 */
export function Favorites({ favorites, expansion, toggle, openContextMenu, openFavorite, add, canAnimateItems }) {
    const { t } = useTypedTranslationWith(/** @type {import('../strings.json')} */ ({}));
    // see: https://www.w3.org/WAI/ARIA/apg/patterns/accordion/examples/accordion/
    const WIDGET_ID = useId();
    const TOGGLE_ID = useId();

    const hiddenCount = expansion === 'collapsed' ? favorites.length - ROW_CAPACITY : 0;
    const rowHeight = ITEM_HEIGHT + ROW_GAP;
    const canToggleExpansion = favorites.length >= ROW_CAPACITY;
    const { data } = useContext(CustomizerContext);
    const { main } = useContext(CustomizerThemesContext);
    const kind = useComputed(() => data.value.background.kind);

    // A flag to determine if animations are available. This is needed
    // because 'view-transition' CSS properties causes an odd experience
    // with filters.
    const animateItems = useComputed(() => {
        return canAnimateItems && kind.value !== 'userImage';
    });

    return (
        <FavoritesThemeContext.Provider value={{ theme: main.value, animateItems }}>
            <div class={styles.root} data-testid="FavoritesConfigured" data-background-kind={kind}>
                <VirtualizedGridRows
                    WIDGET_ID={WIDGET_ID}
                    favorites={favorites}
                    rowHeight={rowHeight}
                    add={add}
                    expansion={expansion}
                    openFavorite={openFavorite}
                    openContextMenu={openContextMenu}
                />
                {canToggleExpansion && (
                    <ShowHideBar>
                        <ShowHideButtonPill
                            buttonAttrs={{
                                'aria-expanded': expansion === 'expanded',
                                'aria-pressed': expansion === 'expanded',
                                'aria-controls': WIDGET_ID,
                                id: TOGGLE_ID,
                            }}
                            text={expansion === 'expanded' ? t('ntp_show_less') : t('ntp_show_more')}
                            label={
                                expansion === 'expanded'
                                    ? t('favorites_show_less')
                                    : t('favorites_show_more', { count: String(hiddenCount) })
                            }
                            onClick={toggle}
                        />
                    </ShowHideBar>
                )}
            </div>
        </FavoritesThemeContext.Provider>
    );
}

/**
 * Favorites Grid. This will take a list of Favorites, split it into chunks (rows)
 * and then layout the rows based on an offset from the top of the container.
 *
 * Doing this means we can just render the items in the current viewport
 *
 * @param {object} props
 * @param {string} props.WIDGET_ID
 * @param {number} props.rowHeight
 * @param {Expansion} props.expansion
 * @param {Favorite[]} props.favorites
 * @param {(id: string) => void} props.openContextMenu
 * @param {(id: string, url: string, target: OpenTarget) => void} props.openFavorite
 * @param {() => void} props.add
 */
function VirtualizedGridRows({ WIDGET_ID, rowHeight, favorites, expansion, openFavorite, openContextMenu, add }) {
    const platformName = usePlatformName();
    const visibility = useDocumentVisibility();

    // convert the list of favorites into chunks of length ROW_CAPACITY
    const rows = useMemo(() => {
        const chunked = [];
        let inner = [];
        for (let i = 0; i < favorites.length; i++) {
            inner.push(favorites[i]);
            if (inner.length === ROW_CAPACITY) {
                chunked.push(inner.slice());
                inner = [];
            }
            if (i === favorites.length - 1) {
                chunked.push(inner.slice());
                inner = [];
            }
        }
        return chunked;
    }, [favorites]);

    // get a ref for the favorites' grid, this will allow it to receive drop events,
    // and the ref can also be used for reading the offset (eg: if other elements are above it)
    const safeAreaRef = /** @type {import("preact").RefObject<HTMLDivElement>} */ (useDropzoneSafeArea());

    // prettier-ignore
    const containerHeight = expansion === 'collapsed' || rows.length === 0
        ? rowHeight
        : rows.length * rowHeight;

    const clickHandler = getOnClickHandler(openFavorite, platformName);
    useOnMiddleClick(safeAreaRef, clickHandler);

    return (
        <div
            className={styles.grid}
            style={{ height: containerHeight + 'px' }}
            id={WIDGET_ID}
            ref={safeAreaRef}
            onContextMenu={getContextMenuHandler(openContextMenu)}
            onClick={clickHandler}
        >
            {rows.length === 0 && <TileRow key={'empty-rows'} items={[]} topOffset={0} add={add} visibility={'visible'} />}
            {rows.length > 0 && <Inner rows={rows} safeAreaRef={safeAreaRef} rowHeight={rowHeight} add={add} visibility={visibility} />}
        </div>
    );
}

/**
 * This is a potentially expensive operation. Especially when going from 'collapsed' to expanded. So, we force
 * the tiles to render after the main thread is cleared by NOT using the 'expansion' from the parent, but instead
 * subscribing to the same update asynchronously. If we accepted the 'expansion' prop in this component and used
 * it directly, it would cause the browser to lock up (on slow devices) when expanding from 1 row to a full screen.
 *
 * @param {object} props
 * @param {Favorite[][]} props.rows
 * @param {import("preact").RefObject<HTMLDivElement>} props.safeAreaRef
 * @param {number} props.rowHeight
 * @param {DocumentVisibilityState} props.visibility
 * @param {()=>void} props.add
 */
function Inner({ rows, safeAreaRef, rowHeight, add, visibility }) {
    const { onConfigChanged, state } = useContext(FavoritesContext);
    const [expansion, setExpansion] = useState(state.config?.expansion || 'collapsed');
    const { start, end } = useVisibleRows(rows, rowHeight, safeAreaRef, expansion);

    // force the children to be rendered after the main thread is cleared
    useEffect(() => {
        return onConfigChanged((config) => {
            // when expanding, wait for the main thread to be clear
            if (config.expansion === 'expanded') {
                setTimeout(() => {
                    setExpansion(config.expansion);
                }, 0);
            } else {
                setExpansion(config.expansion);
            }
        });
    }, [onConfigChanged]);

    // now, we decide which items to show based on the widget expansion
    // prettier-ignore
    const subsetOfRowsToRender = expansion === 'collapsed'
        // if it's 'collapsed', just 1 row to show (the first one)
        ? [rows[0]]
        // otherwise, select the window between start/end
        // the '+ 1' is an additional row to render offscreen - which helps with keyboard navigation.
        : rows.slice(start, end + 1);

    return (
        <Fragment>
            {subsetOfRowsToRender.map((items, rowIndex) => {
                const topOffset = expansion === 'expanded' ? (start + rowIndex) * rowHeight : 0;
                const keyed = `-${start + rowIndex}-`;
                return <TileRow key={keyed} items={items} topOffset={topOffset} add={add} visibility={visibility} />;
            })}
        </Fragment>
    );
}

/**
 * Calculates and provides the start and end indices of visible rows within a given container
 * based on the specified row height and scroll position. The function is optimized for
 * performance and is designed to work with dynamic resizing and scrolling of the container.
 *
 * @param {Array} rows - The array of rows to be virtually rendered. Each row represents an item in the list.
 * @param {number} rowHeight - The fixed height of each row in pixels.
 * @param {Object} safeAreaRef - A React ref object pointing to the DOM element that serves as the virtualized list’s container.
 * @param {Expansion} expansion - A React ref object pointing to the DOM element that serves as the virtualized list’s container.
 * @return {Object} An object containing the calculated `start` and `end` indices of the visible rows.
 */
function useVisibleRows(rows, rowHeight, safeAreaRef, expansion) {
    // set the start/end indexes of the elements
    const [{ start, end }, setVisibleRange] = useState({ start: 0, end: 1 });

    // hold a mutable value that we update on resize
    const gridOffsetRef = useRef(0);
    const mainScrollerRef = useRef(/** @type {Element|null} */ (null));
    const contentTubeRef = useRef(/** @type {Element|null} */ (null));
    /**
     * When called, make the expensive call to `getBoundingClientRect` to determine the offset of
     * the grid wrapper.
     */
    function updateGlobals() {
        if (!safeAreaRef.current) return;
        const rec = safeAreaRef.current.getBoundingClientRect();
        gridOffsetRef.current = rec.y + mainScrollerRef.current?.scrollTop;
    }

    /**
     * decide which the start/end indexes should be, based on scroll position.
     * NOTE: this is called on scroll, so must not incur expensive checks/measurements - math only!
     * @param {number} rowCount - the number of rows in the dataset
     */
    function setVisibleRowsForOffset(rowCount) {
        if (!safeAreaRef.current) return console.warn('cannot access ref');
        const scrollY = mainScrollerRef.current?.scrollTop ?? 0;
        const offset = gridOffsetRef.current;
        const end = scrollY + window.innerHeight - offset;
        let start;
        if (offset > scrollY) {
            start = 0;
        } else {
            start = scrollY - offset;
        }
        const startIndex = Math.floor(start / rowHeight);
        const endIndex = Math.min(Math.ceil(end / rowHeight), rowCount);

        // don't set state if the offset didn't change
        setVisibleRange((prev) => {
            if (startIndex !== prev.start || endIndex !== prev.end) {
                return { start: startIndex, end: endIndex };
            }
            return prev;
        });
    }

    useLayoutEffect(() => {
        // ignore scrolling events if collapsed
        if (expansion === 'collapsed') return;

        mainScrollerRef.current = document.querySelector('[data-main-scroller]') || document.documentElement;
        contentTubeRef.current = document.querySelector('[data-content-tube]') || document.body;
        if (!contentTubeRef.current || !mainScrollerRef.current) console.warn('missing elements');

        // always update globals first
        updateGlobals();

        // and set visible rows once the size is known
        setVisibleRowsForOffset(rows.length);

        const controller = new AbortController();

        // when the main area is scrolled, update the visible offset for the rows.
        mainScrollerRef.current?.addEventListener(
            'scroll',
            () => {
                setVisibleRowsForOffset(rows.length);
            },
            { signal: controller.signal },
        );

        return () => {
            controller.abort();
        };
    }, [rows.length, expansion]);

    useEffect(() => {
        let lastWindowHeight = window.innerHeight;
        function handler() {
            if (lastWindowHeight === window.innerHeight) return;
            lastWindowHeight = window.innerHeight;
            updateGlobals();
            setVisibleRowsForOffset(rows.length);
        }
        window.addEventListener('resize', handler);
        return () => {
            return window.removeEventListener('resize', handler);
        };
    }, [rows.length]);

    useEffect(() => {
        if (!contentTubeRef.current) return;
        let lastHeight;
        let debounceTimer;
        const resizer = new ResizeObserver((entries) => {
            const first = entries[0];
            if (!first || !first.contentRect) return;
            if (first.contentRect.height !== lastHeight) {
                lastHeight = first.contentRect.height;
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    updateGlobals();
                    setVisibleRowsForOffset(rows.length);
                }, 50);
            }
        });

        resizer.observe(contentTubeRef.current);
        return () => {
            resizer.disconnect();
            clearTimeout(debounceTimer);
        };
    }, [rows.length]);

    return { start, end };
}

/**
 * Handle right-clicks
 *
 * @param {(id: string) => void} openContextMenu
 */
function getContextMenuHandler(openContextMenu) {
    /**
     * @param {MouseEvent} event
     */
    return (event) => {
        let target = /** @type {HTMLElement|null} */ (event.target);
        while (target && target !== event.currentTarget) {
            if (typeof target.dataset.id === 'string' && 'href' in target && typeof target.href === 'string') {
                event.preventDefault();
                event.stopImmediatePropagation();
                return openContextMenu(target.dataset.id);
            } else {
                target = target.parentElement;
            }
        }
    };
}

/**
 * Following a click on a favorite, walk up the DOM from the clicked
 * element to find the <a>. This is done to prevent needing a click handler
 * on every element.
 * @param {(id: string, url: string, target: OpenTarget) => void} openFavorite
 * @param {ImportMeta['platform']} platformName
 */
function getOnClickHandler(openFavorite, platformName) {
    /**
     * @param {MouseEvent} event
     */
    return (event) => {
        const target = /** @type {HTMLElement|null} */ (event.target);
        if (!target) return;
        const anchor = /** @type {HTMLAnchorElement|null} */ (target.closest('a[href][data-id]'));
        if (anchor && anchor.dataset.id) {
            event.preventDefault();
            event.stopImmediatePropagation();
            const openTarget = eventToTarget(event, platformName);
            return openFavorite(anchor.dataset.id, anchor.href, openTarget);
        }
    };
}
