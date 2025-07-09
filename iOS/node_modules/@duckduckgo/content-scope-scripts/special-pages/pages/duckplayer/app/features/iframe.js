import { PIP } from './pip.js';
import { AutoFocus } from './autofocus.js';
import { ClickCapture } from './click-capture.js';
import { TitleCapture } from './title-capture.js';
import { MouseCapture } from './mouse-capture.js';
import { ErrorDetection } from './error-detection.js';
import { ReplaceWatchLinks } from './replace-watch-links.js';

/**
 * @import {EmbedSettings} from '../embed-settings.js';
 */

/**
 * Represents an individual piece of functionality in the iframe.
 *
 * @interface
 */
export class IframeFeature {
    /**
     * @param {HTMLIFrameElement} _iframe
     * @returns {(() => void) | null}
     */

    iframeDidLoad(_iframe) {
        return () => {
            console.log('teardown');
        };
    }

    static noop() {
        return {
            iframeDidLoad: () => {
                return () => {};
            },
        };
    }
}

/**
 * Creates a known set of features for the iframe with access to
 * global `Settings`
 *
 * @param {import("../settings").Settings} settings
 * @param {EmbedSettings} embed
 */
export function createIframeFeatures(settings, embed) {
    return {
        /**
         * @return {IframeFeature}
         */
        pip: () => {
            if (settings.pip.state === 'enabled') {
                return new PIP();
            }
            return IframeFeature.noop();
        },
        /**
         * @return {IframeFeature}
         */
        autofocus: () => {
            return new AutoFocus();
        },
        /**
         * @return {IframeFeature}
         */
        clickCapture: () => {
            return new ClickCapture({
                baseUrl: settings.youtubeBase,
            });
        },
        /**
         * @return {IframeFeature}
         */
        titleCapture: () => {
            return new TitleCapture();
        },
        /**
         * @return {IframeFeature}
         */
        mouseCapture: () => {
            return new MouseCapture();
        },
        /**
         * @return {IframeFeature}
         */
        errorDetection: () => {
            return new ErrorDetection(settings.customError);
        },
        /**
         * @param {() => void} handler - what to invoke when a watch-link was clicked
         * @return {IframeFeature}
         */
        replaceWatchLinks: (handler) => {
            return new ReplaceWatchLinks(embed.videoId.id, handler);
        },
    };
}
