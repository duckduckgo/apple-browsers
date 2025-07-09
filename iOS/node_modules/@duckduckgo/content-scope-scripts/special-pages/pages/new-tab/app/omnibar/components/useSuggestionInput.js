import { useLayoutEffect, useRef } from 'preact/hooks';

/**
 * @param {string} base
 * @param {string} suggestion
 */
export function useSuggestionInput(base, suggestion) {
    const ref = useRef(/** @type {HTMLInputElement|null} */ (null));

    useLayoutEffect(() => {
        if (!ref.current) return;
        const value = base + suggestion;
        ref.current.value = value;
        if (suggestion) {
            ref.current.setSelectionRange(base.length, value.length);
        }
    }, [base, suggestion]);

    return ref;
}
