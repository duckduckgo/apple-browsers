import { useSettings } from '../../types.js';
import { useSignalEffect } from '@preact/signals';
import { useQueryContext } from '../Providers/QueryProvider.js';

/**
 * Updates the URL with the latest search term (if present) and dispatches a custom event with the updated query parameters.
 * Debounces the updates based on the `settings.typingDebounce` value to avoid frequent URL state changes during typing.
 *
 * This hook uses a signal effect to listen for changes in the `derivedTerm` and updates the browser's URL accordingly, with debounce support.
 * It dispatches an `EVENT_SEARCH_COMMIT` event to notify other components or parts of the application about the updated search parameters.
 *
 */
export function useURLReflection() {
    const settings = useSettings();
    const query = useQueryContext();
    useSignalEffect(() => {
        let timer;
        let count = 0;
        const unsubscribe = query.subscribe((nextValue) => {
            if (count === 0) return (count += 1);
            clearTimeout(timer);
            if (nextValue.term !== null) {
                const term = nextValue.term;
                timer = setTimeout(() => {
                    const url = new URL(window.location.href);

                    url.searchParams.set('q', term);
                    url.searchParams.delete('range');
                    url.searchParams.delete('domain');

                    if (term.trim() === '') {
                        url.searchParams.delete('q');
                    }

                    window.history.replaceState(null, '', url.toString());
                }, settings.urlDebounce);
            }
            if (nextValue.domain !== null) {
                const url = new URL(window.location.href);
                url.searchParams.set('domain', nextValue.domain);
                url.searchParams.delete('q');
                url.searchParams.delete('range');

                window.history.replaceState(null, '', url.toString());
            }
            return null;
        });

        return () => {
            unsubscribe();
            clearTimeout(timer);
        };
    });
}
