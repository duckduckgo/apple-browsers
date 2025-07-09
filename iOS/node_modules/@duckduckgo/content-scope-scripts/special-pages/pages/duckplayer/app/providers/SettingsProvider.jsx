import { h } from 'preact';
import { createContext } from 'preact';
import { Settings } from '../settings';
import { useContext } from 'preact/hooks';
import { useMessaging } from '../types.js';

const SettingsContext = createContext(/** @type {{settings: Settings}} */ ({}));

/**
 * @import {EmbedSettings} from '../embed-settings.js';
 */

/**
 * @param {object} params
 * @param {Settings} params.settings
 * @param {import("preact").ComponentChild} params.children
 */
export function SettingsProvider({ settings, children }) {
    return <SettingsContext.Provider value={{ settings }}>{children}</SettingsContext.Provider>;
}

export function usePlatformName() {
    return useContext(SettingsContext).settings.platform.name;
}

export function useLayout() {
    return useContext(SettingsContext).settings.layout;
}

/**
 * Handler for opening settings
 */
export function useOpenSettingsHandler() {
    const settings = useContext(SettingsContext).settings;
    const messaging = useMessaging();
    return () => {
        switch (settings.platform.name) {
            case 'ios':
            case 'android': {
                messaging.openSettings();
                break;
            }
            default: {
                console.warn('unreachable!');
            }
        }
    };
}

export function useSettingsUrl() {
    return 'duck://settings/duckplayer';
}

export function useSettings() {
    return useContext(SettingsContext).settings;
}

/**
 * Handler for opening info
 */
export function useOpenInfoHandler() {
    const settings = useContext(SettingsContext).settings;
    const messaging = useMessaging();
    return () => {
        switch (settings.platform.name) {
            case 'android':
            case 'ios': {
                messaging.openInfo();
                break;
            }
            default: {
                console.warn('unreachable!');
            }
        }
    };
}

/**
 * Handler for opening info
 */
export function useOpenOnYoutubeHandler() {
    const settings = useContext(SettingsContext).settings;
    /**
     * @param {EmbedSettings} embed
     */
    return (embed) => {
        if (!embed) return console.warn('unreachable, settings.embed must be present');
        try {
            const base = new URL(settings.youtubeBase);
            window.location.href = embed.intoYoutubeUrl(base);
        } catch (e) {
            console.error('could not form a URL to open in Youtube', e);
        }
    };
}
