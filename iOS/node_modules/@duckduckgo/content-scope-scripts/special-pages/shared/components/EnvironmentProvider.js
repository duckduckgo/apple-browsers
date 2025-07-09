import { createContext, h } from 'preact';
import { useContext, useEffect, useState } from 'preact/hooks';

const EnvironmentContext = createContext({
    isReducedMotion: false,
    isDarkMode: false,
    debugState: false,
    injectName: /** @type {import('../environment').Environment['injectName']} */ ('windows'),
    willThrow: false,
    /** @type {keyof typeof import('../utils').translationsLocales} */
    locale: 'en',
    /** @type {import('../environment').Environment['env']} */
    env: 'production',
});

const THEME_QUERY = '(prefers-color-scheme: dark)';
const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

/**
 * Provide settings for the application.
 *
 * @param {Object} props - The props for the settings provider.
 * @param {import("preact").ComponentChild} props.children - The children components to be wrapped by the settings provider.
 * @param {boolean} props.debugState - The flag indicating if debug state is enabled.
 * @param {ImportMeta['injectName']} [props.injectName] - The flag indicating if debug state is enabled.
 * @param {import('../environment').Environment['env']} [props.env] - The flag indicating production or development
 * @param {keyof typeof import('../utils').translationsLocales} [props.locale] - The locale to use for the application
 * @param {boolean} [props.willThrow] - used to simulate a fatal exception
 */
export function EnvironmentProvider({
    children,
    debugState,
    env = 'production',
    willThrow = false,
    injectName = 'windows',
    locale = 'en',
}) {
    const [theme, setTheme] = useState(window.matchMedia(THEME_QUERY).matches ? 'dark' : 'light');
    const [isReducedMotion, setReducedMotion] = useState(window.matchMedia(REDUCED_MOTION_QUERY).matches);

    useEffect(() => {
        const mediaQueryList = window.matchMedia(THEME_QUERY);
        const listener = (e) => setTheme(e.matches ? 'dark' : 'light');
        mediaQueryList.addEventListener('change', listener);
        return () => mediaQueryList.removeEventListener('change', listener);
    }, []);

    useEffect(() => {
        // media query
        const mediaQueryList = window.matchMedia(REDUCED_MOTION_QUERY);

        const listener = (e) => setter(e.matches);
        mediaQueryList.addEventListener('change', listener);

        // set the initial value
        setter(mediaQueryList.matches);

        /**
         * @type {(value: boolean) => void} value
         */
        function setter(value) {
            document.documentElement.dataset.reducedMotion = String(value);
            setReducedMotion(value);
        }

        // toggle events on window
        window.addEventListener('toggle-reduced-motion', () => {
            setter(true);
        });

        return () => mediaQueryList.removeEventListener('change', listener);
    }, []);

    return (
        <EnvironmentContext.Provider
            value={{
                isReducedMotion,
                debugState,
                isDarkMode: theme === 'dark',
                injectName,
                willThrow,
                env,
                locale,
            }}
        >
            {children}
        </EnvironmentContext.Provider>
    );
}

/**
 * Update settings based on provided search query.
 *
 * Note: This is here to simulate exactly what native platforms may trigger during their tests
 *
 * ```js
 * window.dispatchEvent(new CustomEvent('toggle-reduced-motion'))
 * ```
 *
 * @param {object} props
 * @param {string} props.search
 */
export function UpdateEnvironment({ search }) {
    useEffect(() => {
        const params = new URLSearchParams(search);
        if (params.has('reduced-motion')) {
            setTimeout(() => {
                window.dispatchEvent(new CustomEvent('toggle-reduced-motion'));
            }, 0);
        }
    }, [search]);
    return null;
}

export function useEnv() {
    return useContext(EnvironmentContext);
}

export function useLocale() {
    return useContext(EnvironmentContext).locale;
}

export function WillThrow() {
    const env = useEnv();
    if (env.willThrow) {
        throw new Error('Simulated Exception');
    }
    return null;
}
