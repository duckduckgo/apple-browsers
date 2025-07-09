import { DuckPlayerNativeYoutube } from './sub-features/duck-player-native-youtube.js';
import { DuckPlayerNativeNoCookie } from './sub-features/duck-player-native-no-cookie.js';
import { DuckPlayerNativeSerp } from './sub-features/duck-player-native-serp.js';

/**
 * @import {DuckPlayerNativeMessages} from './messages.js'
 * @import {Environment} from '../duckplayer/environment.js'
 * @import {TranslationFn} from '../duck-player-native.js'
 * @import {DuckPlayerNativeSettings} from "@duckduckgo/privacy-configuration/schema/features/duckplayer-native.js"
 * @typedef {DuckPlayerNativeSettings['selectors']} DuckPlayerNativeSelectors
 */

/**
 * @interface
 */
export class DuckPlayerNativeSubFeature {
    /**
     * Called immediately when an instance is created
     */
    onInit() {}
    /**
     * Called when the page is in a ready state (could be immediately following 'onInit')
     */
    onLoad() {}
    /**
     * Called when effects should be cleaned up
     */
    destroy() {}
}

/**
 * Sets up Duck Player for a YouTube watch page
 *
 * @param {DuckPlayerNativeSelectors} selectors
 * @param {boolean} paused
 * @param {Environment} environment
 * @param {DuckPlayerNativeMessages} messages
 * @return {DuckPlayerNativeSubFeature}
 */
export function setupDuckPlayerForYouTube(selectors, paused, environment, messages) {
    return new DuckPlayerNativeYoutube({
        selectors,
        environment,
        messages,
        paused,
    });
}

/**
 * Sets up Duck Player for a video player in the YouTube no-cookie domain
 *
 * @param {DuckPlayerNativeSelectors} selectors
 * @param {Environment} environment
 * @param {DuckPlayerNativeMessages} messages
 * @param {TranslationFn} t
 * @return {DuckPlayerNativeSubFeature}
 */
export function setupDuckPlayerForNoCookie(selectors, environment, messages, t) {
    return new DuckPlayerNativeNoCookie({
        selectors,
        environment,
        messages,
        t,
    });
}

/**
 * Sets up Duck Player events for the SERP
 * @return {DuckPlayerNativeSubFeature}
 */
export function setupDuckPlayerForSerp() {
    return new DuckPlayerNativeSerp();
}
