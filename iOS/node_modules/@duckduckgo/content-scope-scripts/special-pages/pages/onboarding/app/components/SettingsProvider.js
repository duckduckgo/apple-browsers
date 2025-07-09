import { h, createContext } from 'preact';
import { useContext } from 'preact/hooks';

const SettingsContext = createContext(/** @type {{platform: {name: ImportMeta['platform']}|undefined}} */ ({}));

/**
 * @param {object} params
 * @param {{name: ImportMeta['platform']}} [params.platform]
 * @param {import("preact").ComponentChild} params.children
 */
export function SettingsProvider({ platform, children }) {
    return <SettingsContext.Provider value={{ platform }}>{children}</SettingsContext.Provider>;
}

export function usePlatformName() {
    return useContext(SettingsContext).platform?.name;
}
