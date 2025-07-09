import { Logger, SideEffects } from '../../duckplayer/util.js';
import { muteAudio } from '../mute-audio.js';
import { pollTimestamp } from '../get-current-timestamp.js';
import { stopVideoFromPlaying, muteAllElements } from '../pause-video.js';
import { showThumbnailOverlay } from '../overlays/thumbnail-overlay.js';

/**
 * @import {DuckPlayerNativeMessages} from '../messages.js'
 * @import {Environment} from '../../duckplayer/environment.js'
 * @import {DuckPlayerNativeSelectors} from '../sub-feature.js'
 */

/**
 * @import {DuckPlayerNativeSubFeature} from "../sub-feature.js"
 * @implements {DuckPlayerNativeSubFeature}
 */
export class DuckPlayerNativeYoutube {
    /**
     * @param {object} options
     * @param {DuckPlayerNativeSelectors} options.selectors
     * @param {Environment} options.environment
     * @param {DuckPlayerNativeMessages} options.messages
     * @param {boolean} options.paused
     */
    constructor({ selectors, environment, messages, paused }) {
        this.environment = environment;
        this.messages = messages;
        this.selectors = selectors;
        this.paused = paused;
        this.sideEffects = new SideEffects({
            debug: environment.isTestMode(),
        });
        this.logger = new Logger({
            id: 'DUCK_PLAYER_NATIVE',
            shouldLog: () => this.environment.isTestMode(),
        });
    }

    onInit() {
        this.sideEffects.add('subscribe to media control', () => {
            return this.messages.subscribeToMediaControl(({ pause }) => {
                this.mediaControlHandler(pause);
            });
        });

        this.sideEffects.add('subscribing to mute audio', () => {
            return this.messages.subscribeToMuteAudio(({ mute }) => {
                this.logger.log('Running mute audio handler. Mute:', mute);
                muteAudio(mute);
            });
        });
    }

    onLoad() {
        this.sideEffects.add('started polling current timestamp', () => {
            const handler = (timestamp) => {
                this.messages.notifyCurrentTimestamp(timestamp.toFixed(0));
            };

            return pollTimestamp(300, handler, this.selectors);
        });

        if (this.paused) {
            this.mediaControlHandler(!!this.paused);
        }
    }

    /**
     * @param {boolean} pause
     */
    mediaControlHandler(pause) {
        this.logger.log('Running media control handler. Pause:', pause);

        const videoElement = this.selectors?.videoElement;
        const videoElementContainer = this.selectors?.videoElementContainer;
        if (!videoElementContainer || !videoElement) {
            this.logger.warn('Missing media control selectors in config');
            return;
        }

        const targetElement = document.querySelector(videoElementContainer);
        if (targetElement) {
            // Prevent repeat execution
            if (this.paused === pause) return;
            this.paused = pause;

            if (pause) {
                this.sideEffects.add('stopping video from playing', () => stopVideoFromPlaying(videoElement));
                this.sideEffects.add('muting all elements', () => muteAllElements());
                this.sideEffects.add('appending thumbnail', () => {
                    const clickHandler = () => {
                        this.messages.notifyOverlayDismissed();
                        this.mediaControlHandler(false);
                    };
                    return showThumbnailOverlay(/** @type {HTMLElement} */ (targetElement), this.environment, clickHandler);
                });
            } else {
                this.sideEffects.destroy('stopping video from playing');
                this.sideEffects.destroy('muting all elements');
                this.sideEffects.destroy('appending thumbnail');
            }
        }
    }

    destroy() {
        this.sideEffects.destroy();
    }
}
