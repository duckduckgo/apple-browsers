import { useSelectionDispatch } from '../Providers/SelectionProvider.js';
import { useCallback } from 'preact/hooks';

/**
 * Custom hook that creates a callback function to handle click events occurring outside of specified elements.
 * The callback dispatches a reset action when the click event target is not a button or an anchor element.
 */
export function useClickAnywhereElse() {
    const dispatch = useSelectionDispatch();
    return useCallback(
        (e) => {
            if (e.target?.closest?.('button,a') === null) {
                dispatch({ kind: 'reset', reason: 'click occurred outside of rows' });
            }
        },
        [dispatch],
    );
}
