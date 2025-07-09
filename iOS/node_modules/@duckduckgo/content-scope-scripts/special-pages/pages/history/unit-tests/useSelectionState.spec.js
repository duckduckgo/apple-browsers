import { test } from 'node:test';
import { deepEqual } from 'node:assert/strict';
import { reducer } from '../app/global/hooks/useSelectionState.js';

/**
 * @typedef {import('../app/global/hooks/useSelectionState.js').Action} Action
 * @typedef {import('../app/global/hooks/useSelectionState.js').SelectionState} SelectionState
 */

/** @type {(a: Action) => Action} */
const create = (a) => a;

/**
 * @satisfies {SelectionState}
 */
const defaultState = {
    anchorIndex: null,
    focusedIndex: null,
    lastShiftRange: { start: null, end: null },
    selected: new Set(),
    lastAction: null,
};

test.describe('reducer function', () => {
    test('should handle "reset" action', () => {
        const prevState = {
            ...defaultState,
            anchorIndex: 5,
            focusedIndex: 5,
            selected: new Set([5]),
        };
        const action = create({ kind: 'reset' });

        const result = reducer(prevState, action);
        deepEqual(result, {
            ...defaultState,
            lastAction: null,
        });
    });

    test('should handle "move-selection" action (direction: up)', () => {
        const prevState = {
            ...defaultState,
            focusedIndex: 3,
        };
        const action = create({ kind: 'move-selection', direction: 'up', total: 10 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 2,
            focusedIndex: 2,
            lastShiftRange: { start: null, end: null },
            selected: new Set([2]),
            lastAction: null,
        });
    });

    test('should handle "move-selection" action (direction: down)', () => {
        const prevState = {
            ...defaultState,
            focusedIndex: 3,
        };
        const action = create({ kind: 'move-selection', direction: 'down', total: 10 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 4,
            focusedIndex: 4,
            lastShiftRange: { start: null, end: null },
            selected: new Set([4]),
            lastAction: null,
        });
    });

    test('should handle "select-index" action', () => {
        const prevState = { ...defaultState };
        const action = create({ kind: 'select-index', index: 2 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 2,
            focusedIndex: 2,
            lastShiftRange: { start: null, end: null },
            selected: new Set([2]),
            lastAction: null,
        });
    });

    test('should handle "toggle-index" action (add to selection)', () => {
        const prevState = { ...defaultState, selected: new Set([1]) };
        const action = create({ kind: 'toggle-index', index: 2 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 2,
            focusedIndex: 2,
            lastShiftRange: { start: null, end: null },
            selected: new Set([1, 2]),
            lastAction: null,
        });
    });

    test('should handle "toggle-index" action (remove from selection)', () => {
        const prevState = { ...defaultState, selected: new Set([1, 2]) };
        const action = create({ kind: 'toggle-index', index: 2 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 2,
            focusedIndex: 2,
            lastShiftRange: { start: null, end: null },
            selected: new Set([1]),
            lastAction: null,
        });
    });

    test('should handle "expand-selected-to-index" action', () => {
        const prevState = { ...defaultState, anchorIndex: 1, selected: new Set([1]) };
        const action = create({ kind: 'expand-selected-to-index', index: 4 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            ...prevState,
            lastShiftRange: { start: 1, end: 4 },
            focusedIndex: 4,
            selected: new Set([1, 2, 3, 4]),
            lastAction: null,
        });
    });

    test('should handle "increment-selection" action (direction: up)', () => {
        const prevState = {
            ...defaultState,
            focusedIndex: 3,
            anchorIndex: 3,
            selected: new Set([3]),
        };
        const action = create({ kind: 'increment-selection', direction: 'up', total: 10 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 3,
            focusedIndex: 2,
            lastShiftRange: { start: 2, end: 3 },
            selected: new Set([2, 3]),
            lastAction: null,
        });
    });

    test('should handle "increment-selection" action (direction: down)', () => {
        const prevState = {
            ...defaultState,
            focusedIndex: 2,
            anchorIndex: 2,
            selected: new Set([2]),
        };
        const action = create({ kind: 'increment-selection', direction: 'down', total: 10 });

        const result = reducer(prevState, action);
        deepEqual(result, {
            anchorIndex: 2,
            focusedIndex: 3,
            lastShiftRange: { start: 2, end: 3 },
            selected: new Set([2, 3]),
            lastAction: null,
        });
    });
});
