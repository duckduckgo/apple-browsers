import { useEffect } from 'preact/hooks';
import { usePlatformName } from '../../types.js';
import { eventToTarget } from '../../../../../shared/handlers.js';
import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';

/**
 * Registers click event handlers for anchor links (`<a>` elements) having `href` and `data-url` attributes.
 * Directs the `click` events with these links to interact with the provided history service.
 *
 * - Anchors with `data-url` attribute are intercepted, and their URLs are processed to determine
 *   the target action (`new-tab`, `same-tab`, or `new-window`) based on the click event details.
 * - Prevents default navigation and propagation for handled events.
 */
export function useLinkClickHandler() {
    const platformName = usePlatformName();
    const dispatch = useHistoryServiceDispatch();
    useEffect(() => {
        /**
         * Handles double-click events, and tries to open a link.
         *
         * @param {MouseEvent} event - The mouse event triggered by a click.
         * @returns {void} - No return value.
         */
        function dblClickHandler(event) {
            const url = closestUrl(event);
            if (url) {
                event.preventDefault();
                event.stopImmediatePropagation();
                const target = eventToTarget(event, platformName);
                dispatch({ kind: 'open-url', url, target });
            }
        }

        /**
         * Handles keydown events, specifically for Space or Enter keys, on anchor links.
         *
         * @param {KeyboardEvent} event - The keyboard event triggered by a keydown action.
         * @returns {void} - No return value.
         */
        function keydownHandler(event) {
            if (event.key !== 'Enter' && event.key !== ' ') return;
            const url = closestUrl(event);
            if (url) {
                event.preventDefault();
                event.stopImmediatePropagation();
                const target = eventToTarget(event, platformName);
                dispatch({ kind: 'open-url', url, target });
            }
        }

        document.addEventListener('keydown', keydownHandler);
        document.addEventListener('dblclick', dblClickHandler);

        return () => {
            document.removeEventListener('dblclick', dblClickHandler);
            document.removeEventListener('keydown', keydownHandler);
        };
    }, [platformName, dispatch]);
}

/**
 * @param {KeyboardEvent|MouseEvent} event
 * @return {string|null}
 */
function closestUrl(event) {
    if (!(event.target instanceof Element)) return null;
    const row = /** @type {HTMLDivElement|null} */ (event.target.closest('[aria-selected]'));
    const anchor = /** @type {HTMLAnchorElement|null} */ (row?.querySelector('a[href][data-url]'));
    const url = anchor?.dataset.url;
    return url || null;
}
