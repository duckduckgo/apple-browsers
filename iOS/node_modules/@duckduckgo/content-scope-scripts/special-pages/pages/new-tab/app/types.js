import { useContext } from 'preact/hooks';
import { TranslationContext } from '../../../shared/components/TranslationsProvider.js';
import { createContext } from 'preact';

/**
 * @import json from './strings.json';
 * @import { InitialSetupResponse } from "../types/new-tab.js";
 */

/**
 * This is a wrapper to only allow keys from the default translation file
 * @type {() => { t: (key: keyof json, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslation() {
    return {
        t: useContext(TranslationContext).t,
    };
}

/**
 * This is a wrapper to only allow keys from the default translation file + contextual ones
 * @template {Record<string, any>} T
 * @param {T} _context
 * @returns {{ t: (key: keyof json|keyof T, replacements?: Record<string, string>) => string }}
 */
export function useTypedTranslationWith(_context) {
    return {
        /** @type {any} */
        t: useContext(TranslationContext).t,
    };
}

export const MessagingContext = createContext(/** @type {import("../src/index.js").NewTabPage} */ ({}));
export const useMessaging = () => {
    const ctx = useContext(MessagingContext);
    if (!ctx) console.warn('missing MessagingContext');
    return ctx;
};
export const TelemetryContext = createContext(
    /** @type {import("./telemetry/telemetry.js").Telemetry} */ ({
        measureFromPageLoad: () => {},
    }),
);
export const useTelemetry = () => useContext(TelemetryContext);

export const InitialSetupContext = createContext(/** @type {InitialSetupResponse} */ ({}));
export const useInitialSetupData = () => useContext(InitialSetupContext);
export const useSettings = () => useContext(InitialSetupContext);
