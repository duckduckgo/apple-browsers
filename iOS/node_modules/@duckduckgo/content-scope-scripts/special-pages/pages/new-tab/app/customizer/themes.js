import { useComputed, useSignal, useSignalEffect } from '@preact/signals';
import { inferSchemeFrom, themeFromBrowser } from '../components/BackgroundProvider.js';

const THEME_QUERY = '(prefers-color-scheme: dark)';
const mediaQueryList = window.matchMedia(THEME_QUERY);

/**
 * @param {import("@preact/signals").Signal<import('../../types/new-tab.js').CustomizerData>} data
 */
export function useThemes(data) {
    /** @type {import("@preact/signals").Signal<'light' | 'dark'>} */
    const mq = useSignal(mediaQueryList.matches ? 'dark' : 'light');

    useSignalEffect(() => {
        const listener = (e) => {
            mq.value = e.matches ? 'dark' : 'light';
        };
        mediaQueryList.addEventListener('change', listener);
        return () => mediaQueryList.removeEventListener('change', listener);
    });

    const main = useComputed(() => {
        return inferSchemeFrom(data.value.background, data.value.theme, mq.value).bg;
    });

    const browser = useComputed(() => {
        return themeFromBrowser(data.value.theme, mq.value);
    });

    return { main, browser };
}
