import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';
import { useSettings } from '../../types.js';
import { useSignalEffect } from '@preact/signals';
import { useQueryContext } from '../Providers/QueryProvider.js';

/**
 * Updates the URL with the latest search term (if present) and dispatches a custom search commit event.
 * Utilizes a debounce mechanism to ensure the URL updates are not performed too often during typing.
 *
 * Workflow:
 * - Listens for changes in the `derivedTerm` signal.
 * - For the first signal emission (`counter === 0`), skips processing to avoid triggering on initial load.
 * - Debounces subsequent changes using `settings.typingDebounce`.
 * - If a non-null value is provided, constructs query parameters with the new term and dispatches
 *   an `EVENT_SEARCH_COMMIT` event with the updated parameters.
 * - If the value is `null`, no action is taken.
 */
export function useSearchCommit() {
    const dispatch = useHistoryServiceDispatch();
    const settings = useSettings();
    const query = useQueryContext();
    useSignalEffect(() => {
        let timer;
        let count = 0;
        const unsubscribe = query.subscribe((next) => {
            if (count === 0) return (count += 1);
            clearTimeout(timer);
            if (next.term !== null) {
                const term = next.term;
                const source = next.source;
                timer = setTimeout(() => {
                    const params = new URLSearchParams();
                    params.set('q', term);
                    dispatch({ kind: 'search-commit', params, source });
                }, settings.typingDebounce);
            }
            if (next.domain !== null) {
                const params = new URLSearchParams();
                params.set('domain', next.domain);
                dispatch({ kind: 'search-commit', params, source: next.source });
            }
            return null;
        });
        return () => {
            unsubscribe();
            clearTimeout(timer);
        };
    });
}
