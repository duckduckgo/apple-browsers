/**
 *
 * Duck Player Overlays are either the small Dax icons that appear on top of video thumbnails
 * when browsing YouTube. These icons allow users to open the video in Duck Player.
 *
 * On the YouTube player page, the main Duck Player Overlay also allows users to open the video
 * in Duck Player, or dismiss the overlay.
 *
 * #### Messages:
 *
 * On Page Load
 *   - {@link DuckPlayerOverlayMessages.initialSetup} is initially called to get the current settings
 *   - {@link DuckPlayerOverlayMessages.onUserValuesChanged} subscription begins immediately - it will continue to listen for updates
 *   - {@link DuckPlayerOverlayMessages.onUIValuesChanged} subscription begins immediately - it will continue to listen for updates
 *
 * Then the following message can be sent at any time
 *   - {@link DuckPlayerOverlayMessages.setUserValues}
 *   - {@link DuckPlayerOverlayMessages.openDuckPlayer}
 *
 * Please see {@link DuckPlayerOverlayMessages} for the up-to-date list
 *
 * ## Remote Config
 *
 *   - Please see {@link OverlaysFeatureSettings} for docs on the individual fields
 *
 * All features are **off** by default. Remote config is then used to selectively enable features.
 *
 * For example, to enable the Duck Player Overlay on YouTube, the following config is used:
 *
 * [📝 JSON example](../../integration-test/test-pages/duckplayer/config/overlays-live.json)
 *
 * @module Duck Player Overlays
 */
import ContentFeature from '../content-feature.js';

import { DuckPlayerOverlayMessages, OpenInDuckPlayerMsg, Pixel } from './duckplayer/overlay-messages.js';
import { isBeingFramed } from '../utils.js';
import { initOverlays } from './duckplayer/overlays.js';
import { Environment } from './duckplayer/environment.js';

/**
 * @typedef UserValues - A way to communicate user settings
 * @property {{enabled: {}} | {alwaysAsk:{}} | {disabled:{}}} privatePlayerMode - one of 3 values
 * @property {boolean} overlayInteracted - always a boolean
 */

/**
 * @typedef UISettings - UI-specific settings
 * @property {boolean} [allowFirstVideo] - should the first video be allowed to load/play?
 * @property {boolean} [playInDuckPlayer] - Forces next video to be played in Duck Player regardless of user setting
 */

/**
 * @typedef OverlaysInitialSettings - The initial payload used to communicate render-blocking information
 * @property {UserValues} userValues
 * @property {UISettings} ui
 */

/**
 * @internal
 */
export default class DuckPlayerFeature extends ContentFeature {
    init(args) {
        /**
         * This feature never operates in a frame
         */
        if (isBeingFramed()) return;

        /**
         * Just the 'overlays' part of the settings object.
         * @type {import("@duckduckgo/privacy-configuration/schema/features/duckplayer").DuckPlayerSettings['overlays']}
         */
        const overlaySettings = this.getFeatureSetting('overlays');
        const overlaysEnabled = overlaySettings?.youtube?.state === 'enabled';

        /**
         * Serp proxy
         */
        const serpProxyEnabled = overlaySettings?.serpProxy?.state === 'enabled';

        /**
         * Bail if no features are enabled
         */
        if (!overlaysEnabled && !serpProxyEnabled) {
            return;
        }

        /**
         * Bail if no messaging backend - this is a debugging feature to ensure we don't
         * accidentally enabled this
         */
        if (!this.messaging) {
            throw new Error('cannot operate duck player without a messaging backend');
        }

        const locale = args?.locale || args?.language || 'en';
        const env = new Environment({
            debug: this.isDebug,
            injectName: import.meta.injectName,
            platform: this.platform,
            locale,
        });
        const comms = new DuckPlayerOverlayMessages(this.messaging, env);

        if (overlaysEnabled) {
            initOverlays(overlaySettings.youtube, env, comms);
        } else if (serpProxyEnabled) {
            comms.serpProxy();
        }
    }
}

/**
 * @typedef {Omit<import("@duckduckgo/privacy-configuration/schema/features/duckplayer").DuckPlayerSettings['overlays']['youtube'], "state">} OverlaysFeatureSettings
 */

// for docs generation
export { DuckPlayerOverlayMessages, OpenInDuckPlayerMsg, Pixel };
