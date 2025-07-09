import { useEffect } from 'preact/hooks';
import { BTN_ACTION_ENTRIES_MENU, KNOWN_ACTIONS } from '../../constants.js';
import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';
import { useSelected } from '../Providers/SelectionProvider.js';

/**
 * This function registers button click handlers that communicate with the history service.
 * Depending on the `data-action` attribute of the clicked button, it triggers a specific action
 * in the service, such as opening a menu, deleting a range, or deleting all entries.
 *
 * - "entries_menu": Triggers the `entriesMenu` method with the button value and dataset index.
 */
export function useButtonClickHandler() {
    const historyServiceDispatch = useHistoryServiceDispatch();
    const selected = useSelected();
    useEffect(() => {
        function clickHandler(/** @type {MouseEvent} */ event) {
            if (!(event.target instanceof Element)) return;

            // was this a button click?
            const btn = /** @type {HTMLButtonElement|null} */ (event.target.closest('button[data-action]'));
            if (btn === null) return;
            if (btn?.getAttribute('aria-disabled') === 'true') return;

            // if so, was it a known action?
            const action = toKnownAction(btn);
            if (action === null) return;

            // if we get this far, we're going to handle the event
            event.stopImmediatePropagation();
            event.preventDefault();

            switch (action) {
                case BTN_ACTION_ENTRIES_MENU: {
                    const index = parseInt(btn.dataset.index ?? '-1', 10);
                    const withinSelection = selected.value.has(index);
                    if (withinSelection) {
                        historyServiceDispatch({
                            kind: 'show-entries-menu',
                            indexes: [...selected.value],
                        });
                    } else {
                        historyServiceDispatch({
                            kind: 'show-entries-menu',
                            indexes: [Number(btn.dataset.index)],
                        });
                    }
                    return;
                }
                default:
                    return null;
            }
        }

        document.addEventListener('click', clickHandler);
        return () => {
            document.removeEventListener('click', clickHandler);
        };
    }, []);
}

/**
 * Converts an HTML button element with a `data-action` attribute
 * into a known action type, based on the `KNOWN_ACTIONS` array.
 *
 * @param {HTMLButtonElement|null} elem - The button element to parse.
 * @return {KNOWN_ACTIONS[number] | null} - The corresponding known action, or null if invalid.
 */
function toKnownAction(elem) {
    if (!elem) return null;
    const action = elem.dataset.action;
    if (!action) return null;
    if (KNOWN_ACTIONS.includes(/** @type {any} */ (action))) return /** @type {KNOWN_ACTIONS[number]} */ (action);
    return null;
}
