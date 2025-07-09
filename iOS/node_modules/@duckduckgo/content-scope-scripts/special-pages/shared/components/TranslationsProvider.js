import { createContext, h } from 'preact';
import { useEffect, useRef } from 'preact/hooks';
import { apply } from '../translations';

/**
 * @typedef {(key: string, replacements?: Record<string, any>) => string} LocalTranslationFn
 */

export const TranslationContext = createContext({
    /** @type {LocalTranslationFn} */
    t: () => {
        throw new Error('must implement');
    },
});

/**
 * A component that provides translation functionality.
 *
 * @param {Object} props - The component props.
 * @param {import("preact").ComponentChild} [props.children] - The child elements.
 * @param {Record<string, any>} props.translationObject - The translations object.
 * @param {Record<string, any>} props.fallback - The translations object to use when a value is missing.
 * @param {number} [props.textLength] - The length of strings - a number higher than 1 will cause the string to be repeated. Useful for testing.
 */
export function TranslationProvider({ children, translationObject, fallback, textLength = 1 }) {
    /**
     * Retrieves the title related to the input key from the current locale.
     *
     * @type {LocalTranslationFn}
     */
    function t(inputKey, replacements) {
        const subject = translationObject?.[inputKey]?.title || fallback?.[inputKey]?.title;
        return apply(subject, replacements, textLength);
    }

    return <TranslationContext.Provider value={{ t }}>{children}</TranslationContext.Provider>;
}

/**
 * Translates the given string and applies attributes/handlers.
 *
 * This is here as an alternative to a library for now since we're not using any user-inputted
 * values and can trust the translation strings we have
 *
 * @param {Object} props
 * @param {string} props.str - The string to be directly placed into HTML
 * @param {Object} props.values - props/handlers to be applied to elements within the inserted markup
 */
export function Trans({ str, values }) {
    /** @type {import('preact/hooks').MutableRef<HTMLDivElement | null>} */
    const ref = useRef(null);
    /** @type {import('preact/hooks').MutableRef<(()=>void)[]>} */
    const cleanups = useRef([]);

    useEffect(() => {
        if (!ref.current) return;
        const curr = ref.current;
        const cleanupsCurr = cleanups.current;
        Object.entries(values).forEach(([tag, attributes]) => {
            curr.querySelectorAll(tag).forEach((el) => {
                Object.entries(attributes).forEach(([key, value]) => {
                    if (typeof value === 'function') {
                        el.addEventListener(key, value);
                        cleanupsCurr.push(() => el.removeEventListener(key, value));
                    } else {
                        el.setAttribute(key, value);
                    }
                });
            });
        });
        return () => {
            cleanupsCurr.forEach((fn) => fn());
        };
    }, [values, str]);

    return <span ref={ref} dangerouslySetInnerHTML={{ __html: str }} />;
}
