import { useContext } from 'preact/hooks';
import { TranslationContext } from '../../../shared/components/TranslationsProvider.js';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import json from '../public/locales/en/special-error.json';

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof json, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}
