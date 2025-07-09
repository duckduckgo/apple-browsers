import { useComputed, useSignalEffect } from '@preact/signals';
import { useQueryContext } from '../Providers/QueryProvider.js';
import { useResultsData } from '../Providers/HistoryServiceProvider.js';
import { useSelectionDispatch } from '../Providers/SelectionProvider.js';

/**
 * Subscribe to changes in the query, and reset selections when they change
 */
export function useResetSelectionsOnQueryChange() {
    const dispatch = useSelectionDispatch();
    const query = useQueryContext();
    const results = useResultsData();
    const length = useComputed(() => results.value.items.length);

    useSignalEffect(() => {
        let prevLength = 0;
        const unsubs = [
            // when anything about the query changes, reset selections
            query.subscribe(() => {
                dispatch({ kind: 'reset', reason: 'query changed' });
            }),
            // when the size of data is smaller than before, reset
            length.subscribe((newLength) => {
                if (newLength < prevLength) {
                    dispatch({
                        kind: 'reset',
                        reason: `items length shrank from ${prevLength} to ${newLength}`,
                    });
                }
                prevLength = newLength;
            }),
        ];

        return () => {
            for (const unsub of unsubs) {
                unsub();
            }
        };
    });
}
