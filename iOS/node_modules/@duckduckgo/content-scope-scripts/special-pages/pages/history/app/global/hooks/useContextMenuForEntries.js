import { useEffect } from 'preact/hooks';
import { useSelected } from '../Providers/SelectionProvider.js';
import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';

/**
 * Support for context menu on entries. This needs to be aware of
 * selected regions so that it can either trigger a context menu
 * for a group, or a single item
 */
export function useContextMenuForEntries() {
    const selected = useSelected();
    const dispatch = useHistoryServiceDispatch();

    useEffect(() => {
        function contextMenu(event) {
            const target = /** @type {HTMLElement|null} */ (event.target);
            if (!(target instanceof HTMLElement)) return;

            // only act on history entries
            const elem = target.closest('[data-history-entry]');
            if (!elem || !(elem instanceof HTMLElement)) return;

            event.preventDefault();
            event.stopImmediatePropagation();

            const isSelected = elem.getAttribute('aria-selected') === 'true';
            if (isSelected) {
                dispatch({ kind: 'show-entries-menu', indexes: [...selected.value] });
            } else {
                dispatch({ kind: 'show-entries-menu', indexes: [Number(elem.dataset.index)] });
            }
        }

        document.addEventListener('contextmenu', contextMenu);

        return () => {
            document.removeEventListener('contextmenu', contextMenu);
        };
    }, []);
}
