import { useSignal } from '@preact/signals';
import { useLayoutEffect } from 'preact/hooks';

/**
 * This hook listens to changes in the viewport width and provides a
 * reactive signal indicating whether the layout mode should be 'reduced'
 * or 'normal'.
 *
 * - 'reduced': For narrow viewports (width <= 799px).
 * - 'normal': For wider viewports (width > 799px).
 *
 * @returns {import('@preact/signals').ReadonlySignal<'reduced' | 'normal'>}
 *          A signal representing the current layout mode ('reduced' or 'normal').
 */
export function useLayoutMode() {
    const mode = useSignal(/** @type {'reduced' | 'normal'} */ (window.matchMedia('(max-width: 799px)').matches ? 'reduced' : 'normal'));

    useLayoutEffect(() => {
        const mediaQuery = window.matchMedia('(max-width: 799px)');
        const handleChange = () => {
            mode.value = mediaQuery.matches ? 'reduced' : 'normal';
        };

        handleChange();
        mediaQuery.addEventListener('change', handleChange);

        return () => {
            mediaQuery.removeEventListener('change', handleChange);
        };
    }, []);

    return mode;
}
