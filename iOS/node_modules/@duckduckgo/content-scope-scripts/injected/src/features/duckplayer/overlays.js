import { DomState } from './util.js';
import { ClickInterception, Thumbnails } from './thumbnails.js';
import { VideoOverlay } from './video-overlay.js';
import { registerCustomElements } from './components/index.js';

/**
 * @typedef {object} OverlayOptions
 * @property {import("../duck-player.js").UserValues} userValues
 * @property {import("../duck-player.js").OverlaysFeatureSettings} settings
 * @property {import("../duck-player.js").DuckPlayerOverlayMessages} messages
 * @property {import("../duck-player.js").UISettings} ui
 * @property {import("./environment.js").Environment} environment
 */

/**
 * @param {import("../duck-player.js").OverlaysFeatureSettings} settings - methods to read environment-sensitive things like the current URL etc
 * @param {import("./environment.js").Environment} environment - methods to read environment-sensitive things like the current URL etc
 * @param {import("./overlay-messages.js").DuckPlayerOverlayMessages} messages - methods to communicate with a native backend
 */
export async function initOverlays(settings, environment, messages) {
    // bind early to attach all listeners
    const domState = new DomState();

    /** @type {import("../duck-player.js").OverlaysInitialSettings} */
    let initialSetup;
    try {
        initialSetup = await messages.initialSetup();
    } catch (e) {
        console.warn(e);
        return;
    }

    if (!initialSetup) {
        console.warn('cannot continue without user settings');
        return;
    }

    let { userValues, ui } = initialSetup;

    /**
     * Create the instance - this might fail if settings or user preferences prevent it
     * @type {Thumbnails|ClickInterception|null}
     */
    let thumbnails = thumbnailsFeatureFromOptions({ userValues, settings, messages, environment, ui });
    let videoOverlays = videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui });

    if (thumbnails || videoOverlays) {
        if (videoOverlays) {
            registerCustomElements();
            videoOverlays?.init('page-load');
        }
        domState.onLoaded(() => {
            // start initially
            thumbnails?.init();

            // now add video overlay specific stuff
            if (videoOverlays) {
                // there was an issue capturing history.pushState, so just falling back to
                let prev = globalThis.location.href;
                setInterval(() => {
                    if (globalThis.location.href !== prev) {
                        videoOverlays?.init('href-changed');
                    }
                    prev = globalThis.location.href;
                }, 500);
            }
        });
    }

    function update() {
        thumbnails?.destroy();
        videoOverlays?.destroy();

        // re-create thumbs
        thumbnails = thumbnailsFeatureFromOptions({ userValues, settings, messages, environment, ui });
        thumbnails?.init();

        // re-create video overlay
        videoOverlays = videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui });
        videoOverlays?.init('preferences-changed');
    }

    /**
     * Continue to listen for updated preferences and try to re-initiate
     */
    messages.onUserValuesChanged((_userValues) => {
        userValues = _userValues;
        update();
    });

    /**
     * Continue to listen for updated UI settings and try to re-initiate
     */
    messages.onUIValuesChanged((_ui) => {
        ui = _ui;
        update();
    });
}

/**
 * @param {OverlayOptions} options
 * @returns {Thumbnails | ClickInterception | null}
 */
function thumbnailsFeatureFromOptions(options) {
    return thumbnailOverlays(options) || clickInterceptions(options);
}

/**
 * @param {OverlayOptions} options
 * @return {Thumbnails | null}
 */
function thumbnailOverlays({ userValues, settings, messages, environment, ui }) {
    // bail if not enabled remotely
    if (settings.thumbnailOverlays.state !== 'enabled') return null;

    const conditions = [
        // must be in 'always ask' mode
        'alwaysAsk' in userValues.privatePlayerMode,
        // must not be set to play in DuckPlayer
        ui?.playInDuckPlayer !== true,
        // must be a desktop layout
        environment.layout === 'desktop',
    ];

    // Only show thumbnails if ALL conditions above are met
    if (!conditions.every(Boolean)) return null;

    return new Thumbnails({
        environment,
        settings,
        messages,
    });
}

/**
 * @param {OverlayOptions} options
 * @return {ClickInterception | null}
 */
function clickInterceptions({ userValues, settings, messages, environment, ui }) {
    // bail if not enabled remotely
    if (settings.clickInterception.state !== 'enabled') return null;

    const conditions = [
        // either enabled via prefs
        'enabled' in userValues.privatePlayerMode,
        // or has a one-time override
        ui?.playInDuckPlayer === true,
    ];

    // Intercept clicks if ANY of the conditions above are met
    if (!conditions.some(Boolean)) return null;

    return new ClickInterception({
        environment,
        settings,
        messages,
    });
}

/**
 * @param {OverlayOptions} options
 * @returns {VideoOverlay | undefined}
 */
function videoOverlaysFeatureFromSettings({ userValues, settings, messages, environment, ui }) {
    if (settings.videoOverlays.state !== 'enabled') return undefined;

    return new VideoOverlay({ userValues, settings, environment, messages, ui });
}
