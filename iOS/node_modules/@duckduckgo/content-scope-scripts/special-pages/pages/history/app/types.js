import { useContext } from 'preact/hooks';
import { TranslationContext } from '../../../shared/components/TranslationsProvider.js';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import json from '../public/locales/en/history.json';
import { createContext } from 'preact';
import { Settings } from './Settings.js';

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof json, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}

export const MessagingContext = createContext(/** @type {import("../src/index.js").HistoryPage} */ ({}));
export const useMessaging = () => useContext(MessagingContext);
export const SettingsContext = createContext(new Settings({ platform: { name: 'macos' } }));
export const useSettings = () => useContext(SettingsContext);

export function usePlatformName() {
    return useContext(SettingsContext).platform.name;
}
