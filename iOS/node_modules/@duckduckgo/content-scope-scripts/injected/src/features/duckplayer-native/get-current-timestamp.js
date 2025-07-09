/**
 * @import { DuckPlayerNativeSelectors } from './sub-feature.js';
 */

/**
 * @param {string} selector - Selector for the video element
 * @returns {number}
 */
export function getCurrentTimestamp(selector) {
    const video = /** @type {HTMLVideoElement|null} */ (document.querySelector(selector));
    return video?.currentTime || 0;
}

/**
 * Sends the timestamp to the browser at an interval
 *
 * @param {number} interval - Polling interval
 * @param {(timestamp: number) => void} callback - Callback handler for polling event
 * @param {DuckPlayerNativeSelectors} selectors - Selectors for the player
 */
export function pollTimestamp(interval = 300, callback, selectors) {
    if (!callback || !selectors) {
        console.error('Timestamp polling failed. No callback or selectors defined');
        return () => {};
    }

    const isShowingAd = () => {
        return selectors.adShowing && !!document.querySelector(selectors.adShowing);
    };

    const timestampPolling = setInterval(() => {
        if (isShowingAd()) return;
        const timestamp = getCurrentTimestamp(selectors.videoElement);
        callback(timestamp);
    }, interval);

    return () => {
        clearInterval(timestampPolling);
    };
}
