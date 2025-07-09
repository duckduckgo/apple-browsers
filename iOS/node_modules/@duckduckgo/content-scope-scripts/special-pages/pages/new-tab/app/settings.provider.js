import { h, createContext } from 'preact';
import { useContext } from 'preact/hooks';

const SettingsContext = createContext(/** @type {{settings: import("./settings.js").Settings}} */ ({}));

/**
 * @param {object} params
 * @param {import("./settings.js").Settings} params.settings
 * @param {import("preact").ComponentChild} params.children
 */
export function SettingsProvider({ settings, children }) {
    return <SettingsContext.Provider value={{ settings }}>{children}</SettingsContext.Provider>;
}

export function usePlatformName() {
    return useContext(SettingsContext).settings.platform.name;
}

export function useCustomizerDrawerSettings() {
    return useContext(SettingsContext).settings.customizerDrawer;
}

/**
 * @returns {boolean}
 */
export function useBatchedActivityApi() {
    const settings = useContext(SettingsContext).settings;
    return settings.batchedActivityApi.state === 'enabled';
}

/**
 * @returns {boolean}
 */
export function useAdBlocking() {
    const settings = useContext(SettingsContext).settings;
    return settings.adBlocking.state === 'enabled';
}
