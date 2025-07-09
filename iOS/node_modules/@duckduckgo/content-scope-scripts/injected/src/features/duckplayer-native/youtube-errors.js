/**
 * @import {DuckPlayerNativeSettings} from "@duckduckgo/privacy-configuration/schema/features/duckplayer-native.js"
 * @import {Logger} from "../duckplayer/util.js"
 * @typedef {"age-restricted" | "sign-in-required" | "no-embed" | "unknown"} YouTubeError
 */

export const YOUTUBE_ERROR_EVENT = 'ddg-duckplayer-youtube-error';

/** @type {Record<string,YouTubeError>} */
export const YOUTUBE_ERRORS = {
    ageRestricted: 'age-restricted',
    signInRequired: 'sign-in-required',
    noEmbed: 'no-embed',
    unknown: 'unknown',
};

/** @type {YouTubeError[]} */
export const YOUTUBE_ERROR_IDS = Object.values(YOUTUBE_ERRORS);

/**
 * Analyses a node and its children to determine if it contains an error state
 *
 * @param {string} errorSelector
 * @param {Node} [node]
 */
export function checkForError(errorSelector, node) {
    if (node?.nodeType === Node.ELEMENT_NODE) {
        const element = /** @type {HTMLElement} */ (node);
        // Check if element has the error class or contains any children with that class
        const isError = element.matches(errorSelector) || !!element.querySelector(errorSelector);
        return isError;
    }

    return false;
}

/**
 * Attempts to detect the type of error in the YouTube embed iframe
 * @param {Window|null} windowObject
 * @param {string} [signInRequiredSelector]
 * @param {Logger} [logger]
 * @returns {YouTubeError}
 */
export function getErrorType(windowObject, signInRequiredSelector, logger) {
    const currentWindow = /** @type {Window & typeof globalThis & { ytcfg: object }} */ (windowObject);
    const currentDocument = currentWindow.document;

    if (!currentWindow || !currentDocument) {
        logger?.warn('Window or document missing!');
        return YOUTUBE_ERRORS.unknown;
    }

    let playerResponse;

    if (!currentWindow.ytcfg) {
        logger?.warn('ytcfg missing!');
    } else {
        logger?.log('Got ytcfg', currentWindow.ytcfg);
    }

    try {
        const playerResponseJSON = currentWindow.ytcfg?.get('PLAYER_VARS')?.embedded_player_response;
        logger?.log('Player response', playerResponseJSON);

        playerResponse = JSON.parse(playerResponseJSON);
    } catch (e) {
        logger?.log('Could not parse player response', e);
    }

    if (typeof playerResponse === 'object') {
        const {
            previewPlayabilityStatus: { desktopLegacyAgeGateReason, status },
        } = playerResponse;

        // 1. Check for UNPLAYABLE status
        if (status === 'UNPLAYABLE') {
            // 1.1. Check for presence of desktopLegacyAgeGateReason
            if (desktopLegacyAgeGateReason === 1) {
                logger?.log('AGE RESTRICTED ERROR');
                return YOUTUBE_ERRORS.ageRestricted;
            }

            // 1.2. Fall back to embed not allowed error
            logger?.log('NO EMBED ERROR');
            return YOUTUBE_ERRORS.noEmbed;
        }
    }

    // 2. Check for sign-in support link
    try {
        if (signInRequiredSelector && !!currentDocument.querySelector(signInRequiredSelector)) {
            logger?.log('SIGN-IN ERROR');
            return YOUTUBE_ERRORS.signInRequired;
        }
    } catch (e) {
        logger?.log('Sign-in required query failed', e);
    }

    // 3. Fall back to unknown error
    logger?.log('UNKNOWN ERROR');
    return YOUTUBE_ERRORS.unknown;
}
