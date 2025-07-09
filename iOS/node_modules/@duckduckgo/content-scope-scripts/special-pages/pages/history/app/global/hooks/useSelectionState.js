import { useCallback } from 'preact/hooks';
import { useComputed, useSignal } from '@preact/signals';
import { invariant } from '../../utils.js';

/**
 * @typedef {(s: (d: Set<number>) => Set<number>, reason: string) => void} UpdateSelected
 * @typedef {import("../../utils.js").Intention} Intention
 * @typedef {{
 *   focusedIndex: number|null;
 *   anchorIndex: number|null;
 *   lastShiftRange: { end: number|null; start: number|null };
 *   lastAction: Action['kind'] | null;
 *   selected: Set<number>;
 * }} SelectionState
 * @import { ReadonlySignal } from '@preact/signals'
 */

/**
 * @typedef {{kind: 'select-index', index: number, reason?: string}
 *   | {kind: 'toggle-index'; index: number; reason?: string}
 *   | {kind: 'expand-selected-to-index'; index: number; reason?: string}
 *   | {kind: 'inc-or-dec-selected'; nextIndex: number; reason?: string}
 *   | {kind: 'move-selection'; direction: 'up' | 'down'; total: number; reason?: string}
 *   | {kind: 'increment-selection'; direction: 'up' | 'down'; total: number; reason?: string}
 *   | {kind: 'reset'; reason?: string}
 * } Action
 */

/** @satisfies {SelectionState} */
const defaultState = {
    anchorIndex: /** @type {null|number} */ (null),
    /** @type {{start: null|number; end: null|number}} */
    lastShiftRange: {
        start: null,
        end: null,
    },
    focusedIndex: /** @type {null|number} */ (null),
    selected: new Set(/** @type {number[]} */ ([])),
    lastAction: /** @type {Action['kind']|null} */ (null),
};

/**
 * @returns {{
 *   selected: ReadonlySignal<Set<number>>;
 *   state: ReadonlySignal<SelectionState>;
 *   dispatch: (action: Action) => void;
 * }}
 */
export function useSelectionStateApi() {
    const state = useSignal(defaultState);
    const selected = useComputed(() => state.value.selected);
    /**
     * @param {Action} evt
     */
    function dispatcher(evt) {
        const next = reducer(state.value, evt);
        next.lastAction = evt.kind;
        state.value = next;
    }
    const dispatch = useCallback(dispatcher, [state, selected]);
    return { selected, dispatch, state };
}

/**
 * @param {SelectionState} prev
 * @param {Action} evt
 * @return {SelectionState}
 */
export function reducer(prev, evt) {
    switch (evt.kind) {
        case 'reset': {
            return {
                ...defaultState,
            };
        }
        case 'move-selection': {
            const { focusedIndex } = prev;
            invariant(focusedIndex !== null);
            const delta = evt.direction === 'up' ? -1 : 1;
            // either the last item, or current + 1
            const max = Math.min(evt.total - 1, focusedIndex + delta);
            const newIndex = Math.max(0, max);
            const newSelected = new Set([newIndex]);
            return {
                ...prev,
                anchorIndex: newIndex,
                focusedIndex: newIndex,
                lastShiftRange: { start: null, end: null },
                selected: newSelected,
            };
        }
        case 'select-index': {
            const newSelected = new Set([evt.index]);
            return {
                ...prev,
                anchorIndex: evt.index,
                focusedIndex: evt.index,
                lastShiftRange: { start: null, end: null },
                selected: newSelected,
            };
        }
        case 'toggle-index': {
            const newSelected = new Set(prev.selected);
            if (newSelected.has(evt.index)) {
                newSelected.delete(evt.index);
            } else {
                newSelected.add(evt.index);
            }
            return {
                ...prev,
                anchorIndex: evt.index,
                lastShiftRange: { start: null, end: null },
                focusedIndex: evt.index,
                selected: newSelected,
            };
        }
        case 'expand-selected-to-index': {
            const { anchorIndex, lastShiftRange } = prev;
            const newSelected = new Set(prev.selected);

            // If there was a previous shift selection, remove it first
            if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
                for (let i = lastShiftRange.start; i <= lastShiftRange.end; i++) {
                    newSelected.delete(i);
                }
            }

            // Calculate new range bounds from the anchor point
            const start = Math.min(anchorIndex ?? 0, evt.index);
            const end = Math.max(anchorIndex ?? 0, evt.index);

            // Add all items in new range to selection
            for (let i = start; i <= end; i++) {
                newSelected.add(i);
            }

            return {
                ...prev,
                lastShiftRange: { start, end },
                focusedIndex: evt.index,
                selected: newSelected,
            };
        }
        case 'inc-or-dec-selected': {
            const { anchorIndex, lastShiftRange } = prev;
            // Handle shift+arrow selection
            const newSelected = new Set(prev.selected);

            // Remove previous shift range
            if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
                for (let i = lastShiftRange.start; i <= lastShiftRange.end; i++) {
                    newSelected.delete(i);
                }
            }

            // Calculate new range
            const start = Math.min(anchorIndex ?? evt.nextIndex, evt.nextIndex);
            const end = Math.max(anchorIndex ?? evt.nextIndex, evt.nextIndex);

            // Add new range
            for (let i = start; i <= end; i++) {
                newSelected.add(i);
            }
            return {
                ...prev,
                focusedIndex: evt.nextIndex,
                lastShiftRange: { start, end },
                anchorIndex: anchorIndex === null ? evt.nextIndex : anchorIndex,
                selected: newSelected,
            };
        }
        case 'increment-selection': {
            const { focusedIndex, anchorIndex, lastShiftRange } = prev;
            invariant(focusedIndex !== null);
            const delta = evt.direction === 'up' ? -1 : 1;
            const newIndex = Math.max(0, Math.min(evt.total - 1, focusedIndex + delta));

            // Handle shift+arrow selection
            const newSelected = new Set(prev.selected);

            // Remove previous shift range
            if (lastShiftRange.start !== null && lastShiftRange.end !== null) {
                for (let i = lastShiftRange.start; i <= lastShiftRange.end; i++) {
                    newSelected.delete(i);
                }
            }

            // Calculate new range
            const start = Math.min(anchorIndex ?? newIndex, newIndex);
            const end = Math.max(anchorIndex ?? newIndex, newIndex);

            // Add new range
            for (let i = start; i <= end; i++) {
                newSelected.add(i);
            }
            return {
                ...prev,
                focusedIndex: newIndex,
                lastShiftRange: { start, end },
                anchorIndex: anchorIndex === null ? newIndex : anchorIndex,
                selected: newSelected,
            };
        }
        default:
            return prev;
    }
}
