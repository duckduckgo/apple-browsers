import * as constants from './constants.js';

/** @import {YouTubeError} from './error-detection.js' */
/** @import {Environment} from '../duckplayer/environment.js' */

/**
 * @typedef {object} MuteSettings - Settings passed to the onMute callback
 * @property {boolean} mute - Set to true to mute the video, false to unmute
 */

/**
 * @typedef {object} MediaControlSettings - Settings passed to the onMediaControll callback
 * @property {boolean} pause - Set to true to pause the video, false to play
 */

/**
 * @typedef {object} UrlChangeSettings - Settings passed to the onURLChange callback
 * @property {PageType} pageType
 */

/**
 * @typedef {'UNKNOWN'|'YOUTUBE'|'NOCOOKIE'|'SERP'} PageType
 */

/**
 * @import {Messaging} from '@duckduckgo/messaging'
 *
 * A wrapper for all communications.
 *
 * Please see https://duckduckgo.github.io/content-scope-utils/modules/Webkit_Messaging for the underlying
 * messaging primitives.
 */
export class DuckPlayerNativeMessages {
    /**
     * @param {Messaging} messaging
     * @param {Environment} environment
     * @internal
     */
    constructor(messaging, environment) {
        /**
         * @internal
         */
        this.messaging = messaging;
        this.environment = environment;
    }

    /**
     * @returns {Promise<import('../duck-player-native.js').InitialSettings>}
     */
    initialSetup() {
        return this.messaging.request(constants.MSG_NAME_INITIAL_SETUP);
    }

    /**
     * Notifies with current timestamp as a string
     * @param {string} timestamp
     */
    notifyCurrentTimestamp(timestamp) {
        return this.messaging.notify(constants.MSG_NAME_CURRENT_TIMESTAMP, { timestamp });
    }

    /**
     * Subscribe to media control events
     * @param {(mediaControlSettings: MediaControlSettings) => void} callback
     */
    subscribeToMediaControl(callback) {
        return this.messaging.subscribe(constants.MSG_NAME_MEDIA_CONTROL, callback);
    }

    /**
     * Subscribe to mute audio events
     * @param {(muteSettings: MuteSettings) => void} callback
     */
    subscribeToMuteAudio(callback) {
        return this.messaging.subscribe(constants.MSG_NAME_MUTE_AUDIO, callback);
    }

    /**
     * Subscribe to URL change events
     * @param {(urlSettings: UrlChangeSettings) => void} callback
     */
    subscribeToURLChange(callback) {
        return this.messaging.subscribe(constants.MSG_NAME_URL_CHANGE, callback);
    }

    /**
     * Notifies browser of YouTube error
     * @param {YouTubeError} error
     */
    notifyYouTubeError(error) {
        this.messaging.notify(constants.MSG_NAME_YOUTUBE_ERROR, { error });
    }

    /**
     * Notifies browser that the feature is ready
     */
    notifyFeatureIsReady() {
        this.messaging.notify(constants.MSG_NAME_FEATURE_READY, {});
    }

    /**
     * Notifies browser that scripts are ready to be acalled
     */
    notifyScriptIsReady() {
        this.messaging.notify(constants.MSG_NAME_SCRIPTS_READY, {});
    }

    /**
     * Notifies browser that the overlay was dismissed
     */
    notifyOverlayDismissed() {
        this.messaging.notify(constants.MSG_NAME_DISMISS_OVERLAY, {});
    }
}
