import { Fragment, h } from 'preact';
import { memo } from 'preact/compat';
import styles from './VirtualizedList.module.css';
import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';

/**
 * @template T
 * @typedef RenderProps
 * @property {T} item
 * @property {number} index
 * @property {string} cssClassName
 * @property {number} itemTopOffset
 * @property {Record<string, any>} style - inline styles to apply to your element
 *
 */

/**
 * @template T
 * @param {object} props
 * @param {T[]} props.items
 * @param {number[]} props.heights - a list of known heights for every item. This prevents needing to measure on the fly
 * @param {number} props.overscan - how many items should be loaded before and after the current set on screen
 * @param {string} props.scrollingElement - a CSS selector matching a parent element that will scroll
 * @param {(arg: RenderProps<T>) => import("preact").ComponentChild} props.renderItem - A function to render individual items.
 * @param {(end: number)=>void} props.onChange - called when the end number is changed
 */
export function VirtualizedList({ items, heights, overscan, scrollingElement, onChange, renderItem }) {
    const { start, end } = useVisibleRows(items, heights, scrollingElement, overscan);
    const subset = items.slice(start, end + 1);

    /**
     * Also publish the fact that the 'end' range changed - this is how 'fetch more' works
     */
    useEffect(() => {
        onChange?.(end);
    }, [onChange, end]);

    return (
        <Fragment>
            {subset.map((item, rowIndex) => {
                const originalIndex = start + rowIndex;
                const itemTopOffset = heights.slice(0, originalIndex).reduce((acc, item) => acc + item, 0);
                return renderItem({
                    item,
                    index: originalIndex,
                    cssClassName: styles.listItem,
                    itemTopOffset,
                    style: {
                        transform: `translateY(${itemTopOffset}px)`,
                    },
                });
            })}
        </Fragment>
    );
}

export const VisibleItems = memo(VirtualizedList);

/**
 * @param {Array} rows - The array of rows to be virtually rendered. Each row represents an item in the list.
 * @param {number[]} heights - index lookup for known element heights
 * @param {string} scrollerSelector - A CSS selector for tracking the scrollable area
 * @param {number} overscan - how many items to fetch outside the window
 * @return {Object} An object containing the calculated `start` and `end` indices of the visible rows.
 */
function useVisibleRows(rows, heights, scrollerSelector, overscan = 5) {
    // set the start/end indexes of the elements
    const [{ start, end }, setVisibleRange] = useState({ start: 0, end: 1 });

    // hold a mutable value that we update on resize
    const mainScrollerRef = useRef(/** @type {Element|null} */ (null));
    const scrollingSize = useRef(/** @type {number|null} */ (null));

    /**
     * When called, make the expensive calls to `getBoundingClientRect` to measure things
     */
    function updateGlobals() {
        if (!mainScrollerRef.current) return;
        const rec = mainScrollerRef.current.getBoundingClientRect();
        scrollingSize.current = rec.height;
    }

    /**
     * decide which the start/end indexes should be, based on scroll position.
     * NOTE: this is called on scroll, so must not incur expensive checks/measurements - math only!
     */
    function setVisibleRowsForOffset() {
        if (!mainScrollerRef.current) return console.warn('cannot access mainScroller ref');
        if (scrollingSize.current === null) return console.warn('need height');
        const scrollY = mainScrollerRef.current?.scrollTop ?? 0;
        const next = calcVisibleRows(heights || [], scrollingSize.current, scrollY);

        const withOverScan = {
            start: Math.max(next.startIndex - overscan, 0),
            end: next.endIndex + overscan,
        };

        // don't set state if the offset didn't change
        setVisibleRange((prev) => {
            if (withOverScan.start !== prev.start || withOverScan.end !== prev.end) {
                // todo: find a better place to emit this!
                return { start: withOverScan.start, end: withOverScan.end };
            }
            return prev;
        });
    }

    useLayoutEffect(() => {
        mainScrollerRef.current = document.querySelector(scrollerSelector) || document.documentElement;
        if (!mainScrollerRef.current) console.warn('missing elements');

        // always update globals first
        updateGlobals();

        // and set visible rows once the size is known
        setVisibleRowsForOffset();

        const controller = new AbortController();

        // when the main area is scrolled, update the visible offset for the rows.
        mainScrollerRef.current?.addEventListener('scroll', setVisibleRowsForOffset, { signal: controller.signal });

        return () => {
            controller.abort();
        };
    }, [rows, heights, scrollerSelector]);

    useEffect(() => {
        let lastWindowHeight = window.innerHeight;
        function handler() {
            if (lastWindowHeight === window.innerHeight) return;
            lastWindowHeight = window.innerHeight;
            updateGlobals();
            setVisibleRowsForOffset();
        }
        window.addEventListener('resize', handler);
        return () => {
            return window.removeEventListener('resize', handler);
        };
    }, [heights, rows]);

    return { start, end };
}

/**
 * @param {number[]} heights - an array of integers that represents a 1:1 mapping to `rows` - each value is pixels
 * @param {number} space - the height in pixels that we have to fill
 * @param {number} scrollOffset - the y offset in pixels representing scrolling
 * @return {{startIndex: number, endIndex: number}}
 */
function calcVisibleRows(heights, space, scrollOffset) {
    let startIndex = 0;
    let endIndex = 0;
    let currentHeight = 0;

    // Adjust startIndex for the scrollOffset
    for (let i = 0; i < heights.length; i++) {
        if (currentHeight + heights[i] > scrollOffset) {
            startIndex = i;
            break;
        }
        currentHeight += heights[i];
    }

    // Start calculating endIndex from the adjusted startIndex
    currentHeight = 0;
    for (let i = startIndex; i < heights.length; i++) {
        if (currentHeight + heights[i] > space) {
            endIndex = i;
            break;
        }
        currentHeight += heights[i];
        endIndex = i;
    }

    return { startIndex, endIndex };
}
