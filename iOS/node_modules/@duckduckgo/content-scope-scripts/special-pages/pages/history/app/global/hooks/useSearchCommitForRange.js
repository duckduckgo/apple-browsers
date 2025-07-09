import { useHistoryServiceDispatch } from '../Providers/HistoryServiceProvider.js';
import { useQueryContext } from '../Providers/QueryProvider.js';
import { useEffect } from 'preact/hooks';

/**
 * Synchronizes the `derivedRange` signal with the browser's URL and issues a
 * 'search-commit'. This allows any part of the application to change the range and
 * have it synchronised to the URL + trigger a search
 */
export function useSearchCommitForRange() {
    const dispatch = useHistoryServiceDispatch();
    const query = useQueryContext();

    useEffect(() => {
        let timer;
        let counter = 0;
        const sub = query.subscribe((nextQuery) => {
            const { range } = nextQuery;
            if (counter === 0) {
                counter += 1;
                return;
            }
            const url = new URL(window.location.href);

            url.searchParams.delete('q');
            url.searchParams.delete('range');

            if (range !== null) {
                url.searchParams.set('range', range);
                window.history.replaceState(null, '', url.toString());
                dispatch({ kind: 'search-commit', params: new URLSearchParams(url.searchParams), source: 'user' });
            }
        });

        return () => {
            sub();
            clearTimeout(timer);
        };
    }, [query, dispatch]);
}
