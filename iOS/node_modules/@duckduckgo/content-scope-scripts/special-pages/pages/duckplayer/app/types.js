import { useContext } from 'preact/hooks';
import { TranslationContext } from '../../../shared/components/TranslationsProvider.js';
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import json from '../public/locales/en/duckplayer.json';
import { createContext } from 'preact';

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof json, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}

export const MessagingContext = createContext(/** @type {import("../src/index.js").DuckplayerPage} */ ({}));
export const useMessaging = () => useContext(MessagingContext);
export const TelemetryContext = createContext(/** @type {import("../src/index.js").Telemetry} */ ({}));
export const useTelemetry = () => useContext(TelemetryContext);
