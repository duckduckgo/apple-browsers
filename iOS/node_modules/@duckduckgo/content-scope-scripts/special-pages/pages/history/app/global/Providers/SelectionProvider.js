import { createContext, h } from 'preact';
import { useCallback, useContext } from 'preact/hooks';
import { signal, useComputed } from '@preact/signals';
import { usePlatformName } from '../../types.js';
import { eventToIntention } from '../../utils.js';
import { useHistoryServiceDispatch, useResultsData } from './HistoryServiceProvider.js';
import { useSelectionStateApi } from '../hooks/useSelectionState.js';

/**
 * @typedef {(s: (d: Set<number>) => Set<number>, reason: string) => void} UpdateSelected
 * @typedef {import("../../utils.js").Intention} Intention
 * @typedef {import('../hooks/useSelectionState.js').Action} Action
 * @typedef {import('../hooks/useSelectionState.js').SelectionState} SelectionState
 * @import { ReadonlySignal } from '@preact/signals'
 */

const SelectionDispatchContext = createContext(/** @type {(a: Action) => void} */ ((_) => {}));
const SelectionStateContext = createContext(/** @type {ReadonlySignal<SelectionState>} */ (signal({})));

/**
 * Provides a context for the selections + state for managing updates (like keyboard+clicks)
 *
 * @param {Object} props - The properties object for the SelectionProvider component.
 * @param {import("preact").ComponentChild} props.children - The child components that will consume the history service context.
 */
export function SelectionProvider({ children }) {
    const { dispatch, state } = useSelectionStateApi();

    return (
        <SelectionStateContext.Provider value={state}>
            <SelectionDispatchContext.Provider value={dispatch}>{children}</SelectionDispatchContext.Provider>
        </SelectionStateContext.Provider>
    );
}

export function useSelectionState() {
    return useContext(SelectionStateContext);
}

export function useSelected() {
    const state = useContext(SelectionStateContext);
    return useComputed(() => state.value.selected);
}

export function useFocussedIndex() {
    const state = useContext(SelectionStateContext);
    return useComputed(() => state.value.focusedIndex);
}

export function useSelectionDispatch() {
    return useContext(SelectionDispatchContext);
}

/**
 * Handle onClick + keydown events to support most interactions with the list.
 * @param {import('preact/hooks').MutableRef<HTMLElement|null>} mainRef
 */
export function useRowInteractions(mainRef) {
    const platformName = usePlatformName();
    const dispatch = useSelectionDispatch();
    const selected = useSelected();
    const historyDispatch = useHistoryServiceDispatch();
    const results = useResultsData();
    const focusedIndex = useFocussedIndex();

    /**
     * @param {Intention} intention
     * @param {{id: string; index: number}} selection
     * @return {boolean}
     */
    function handleRowClickIntentions(intention, selection) {
        const { index } = selection;
        switch (intention) {
            case 'click':
                dispatch({ kind: 'select-index', index, reason: intention });
                return true;
            case 'ctrl+click': {
                dispatch({ kind: 'toggle-index', index, reason: intention });
                return true;
            }
            case 'shift+click': {
                dispatch({ kind: 'expand-selected-to-index', index, reason: intention });
                return true;
            }
        }
        return false;
    }

    function clickHandler(/** @type {MouseEvent} */ event) {
        if (!(event.target instanceof Element)) return;
        if (event.target.closest('button')) return;
        if (event.target.closest('a')) return;

        const itemRow = /** @type {HTMLElement|null} */ (event.target.closest('[data-history-entry][data-index]'));
        const intention = eventToIntention(event, platformName);
        const selection = toRowSelection(itemRow);
        if (selection) {
            const handled = handleRowClickIntentions(intention, selection);
            if (handled) {
                event.preventDefault();
                event.stopImmediatePropagation();
            }
        }
    }

    /**
     * @param {Intention} intention
     * @return {boolean} true if we handled this event
     */
    function handleKeyIntention(intention) {
        const total = results.value.items.length;
        if (focusedIndex.value === null) return false;

        switch (intention) {
            case 'shift+down': {
                dispatch({
                    kind: 'increment-selection',
                    direction: 'down',
                    total,
                });
                return true;
            }
            case 'shift+up': {
                dispatch({
                    kind: 'increment-selection',
                    direction: 'up',
                    total,
                });
                return true;
            }
            case 'up':
                dispatch({ kind: 'move-selection', direction: 'up', total });
                return true;
            case 'down': {
                dispatch({ kind: 'move-selection', direction: 'down', total });
                return true;
            }
            case 'delete': {
                if (selected.value.size === 0) break;
                historyDispatch({ kind: 'delete-entries-by-index', value: [...selected.value] });
                break;
            }
        }
        return false;
    }
    /**
     * @param {Intention} intention
     * @param {KeyboardEvent} event
     */
    function handleGlobalKeyIntentions(intention, event) {
        if (event.target !== document.body) return false;
        switch (intention) {
            case 'escape': {
                dispatch({
                    kind: 'reset',
                    reason: 'escape key pressed',
                });
                return true;
            }
        }
        return false;
    }

    function keyHandler(/** @type {KeyboardEvent} */ event) {
        const intention = eventToIntention(event, platformName);
        if (intention === 'unknown') return;
        if (focusedIndex.value === null) return;
        let handled = false;

        /**
         * If the target is body OR within the main scroller, handle the events such as selections
         */
        if (
            event.target === document.body ||
            event.target === mainRef.current ||
            mainRef.current?.contains(/** @type {any} */ (event.target))
        ) {
            handled = handleKeyIntention(intention);
        }

        /**
         * If it wasn't handled, try global things like `escape`?
         */
        if (!handled) {
            handled = handleGlobalKeyIntentions(intention, event);
        }

        if (handled) event.preventDefault();
    }

    const onClick = useCallback(clickHandler, [selected, focusedIndex]);
    const onKeyDown = useCallback(keyHandler, [selected, focusedIndex]);

    return { onClick, onKeyDown };
}

/**
 * @param {null|HTMLElement} elem
 * @returns {{id: string; index: number} | null}
 */
function toRowSelection(elem) {
    if (elem === null) return null;
    const { index, historyEntry } = elem.dataset;
    if (typeof historyEntry !== 'string') return null;
    if (typeof index !== 'string') return null;
    if (!index.trim().match(/^\d+$/)) return null;
    return { id: historyEntry, index: parseInt(index, 10) };
}
