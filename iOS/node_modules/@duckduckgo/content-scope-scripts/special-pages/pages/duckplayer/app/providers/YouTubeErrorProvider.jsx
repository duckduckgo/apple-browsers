import { useContext, useState } from 'preact/hooks';
import { h, createContext } from 'preact';
import { useEffect } from 'preact/hooks';
import { useMessaging } from '../types';
import { useSetFocusMode } from '../components/FocusMode';
import { YOUTUBE_ERROR_IDS, YOUTUBE_ERROR_EVENT } from '../../../../../injected/src/features/duckplayer-native/youtube-errors.js';
import { useSettings } from './SettingsProvider';

/**
 * @import {YouTubeError} from '../../types/duckplayer'
 */

const YouTubeErrorContext = createContext({
    /** @type {YouTubeError|null} */
    error: null,
    /** @type {string} - Enables showing different error messages based on locale */
    locale: 'en',
});

/**
 * @param {object} props
 * @param {YouTubeError|null} [props.initial=null]
 * @param {string} props.locale
 * @param {import("preact").ComponentChild} props.children
 */
export function YouTubeErrorProvider({ initial = null, locale, children }) {
    // initial state
    let initialError = null;
    if (initial && YOUTUBE_ERROR_IDS.includes(initial)) {
        initialError = initial;
    }
    const [error, setError] = useState(initialError);

    const messaging = useMessaging();
    const setFocusMode = useSetFocusMode();

    // listen for updates
    useEffect(() => {
        /** @type {(event: CustomEvent) => void} */
        const errorEventHandler = (event) => {
            const eventError = event.detail?.error;
            if (YOUTUBE_ERROR_IDS.includes(eventError) || eventError === null) {
                if (eventError && eventError !== error) {
                    setFocusMode('paused');
                    messaging.reportYouTubeError({ error: eventError });
                } else {
                    setFocusMode('enabled');
                }
                setError(eventError);
            }
        };

        window.addEventListener(YOUTUBE_ERROR_EVENT, errorEventHandler);

        return () => window.removeEventListener(YOUTUBE_ERROR_EVENT, errorEventHandler);
    }, []);

    return <YouTubeErrorContext.Provider value={{ error, locale }}>{children}</YouTubeErrorContext.Provider>;
}

export function useYouTubeError() {
    return useContext(YouTubeErrorContext).error;
}

export function useLocale() {
    return useContext(YouTubeErrorContext).locale;
}

export function useShowCustomError() {
    const settings = useSettings();
    const youtubeError = useContext(YouTubeErrorContext).error;
    return youtubeError !== null && settings.customError?.state === 'enabled';
}
