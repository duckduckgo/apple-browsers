import { usePlatformName } from '../../types.js';
import { useEffect } from 'preact/hooks';
import { eventToTarget } from '../../../../../shared/handlers.js';
import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';

/**
 * Support middle-button click
 */
export function useAuxClickHandler() {
    const platformName = usePlatformName();
    const dispatch = useHistoryServiceDispatch();
    useEffect(() => {
        const handleAuxClick = (event) => {
            const row = /** @type {HTMLDivElement|null} */ (event.target.closest('[aria-selected]'));
            const anchor = /** @type {HTMLAnchorElement|null} */ (row?.querySelector('a[href][data-url]'));
            const url = anchor?.dataset.url;
            if (anchor && url && event.button === 1) {
                event.preventDefault();
                event.stopImmediatePropagation();
                const target = eventToTarget(event, platformName);
                dispatch({ kind: 'open-url', url, target });
            }
        };
        document.addEventListener('auxclick', handleAuxClick);
        return () => {
            document.removeEventListener('auxclick', handleAuxClick);
        };
    }, [platformName, dispatch]);
}
