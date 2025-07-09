import { useContext } from 'preact/hooks';
import { TranslationContext } from '../../../shared/components/TranslationsProvider';

/**
 * @typedef {'PrivacyPro'} NotesIcon // Allows for more icons to be added in the future
 * @typedef {{ icon?: NotesIcon, title?: string, notes: import('preact').ComponentChild[] }} Notes
 */

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof import('../public/locales/en/release-notes.json'), replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}
