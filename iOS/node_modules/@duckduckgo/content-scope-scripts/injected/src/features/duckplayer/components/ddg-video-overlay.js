import css from '../assets/video-overlay.css';
import dax from '../assets/dax.svg';
import { overlayCopyVariants } from '../text.js';
import { appendImageAsBackground } from '../util.js';
import { VideoOverlay } from '../video-overlay.js';
import { createPolicy, html, trustedUnsafe } from '../../../dom-utils.js';

/**
 * The custom element that we use to present our UI elements
 * over the YouTube player
 */
export class DDGVideoOverlay extends HTMLElement {
    policy = createPolicy();

    static CUSTOM_TAG_NAME = 'ddg-video-overlay';
    /**
     * @param {object} options
     * @param {import("../environment.js").Environment} options.environment
     * @param {import("../util").VideoParams} options.params
     * @param {import("../../duck-player.js").UISettings} options.ui
     * @param {VideoOverlay} options.manager
     */
    constructor({ environment, params, ui, manager }) {
        super();
        if (!(manager instanceof VideoOverlay)) throw new Error('invalid arguments');
        this.environment = environment;
        this.ui = ui;
        this.params = params;
        this.manager = manager;

        /**
         * Create the shadow root, closed to prevent any outside observers
         * @type {ShadowRoot}
         */
        const shadow = this.attachShadow({ mode: this.environment.isTestMode() ? 'open' : 'closed' });

        /**
         * Add our styles
         * @type {HTMLStyleElement}
         */
        const style = document.createElement('style');
        style.innerText = css;

        /**
         * Create the overlay
         * @type {HTMLDivElement}
         */
        const overlay = this.createOverlay();

        /**
         * Append both to the shadow root
         */
        shadow.appendChild(overlay);
        shadow.appendChild(style);
    }

    /**
     * @returns {HTMLDivElement}
     */
    createOverlay() {
        const overlayCopy = overlayCopyVariants.default;
        const overlayElement = document.createElement('div');
        overlayElement.classList.add('ddg-video-player-overlay');
        const svgIcon = trustedUnsafe(dax);
        const safeString = html`
            <div class="ddg-vpo-bg"></div>
            <div class="ddg-vpo-content">
                <div class="ddg-eyeball">${svgIcon}</div>
                <div class="ddg-vpo-title">${overlayCopy.title}</div>
                <div class="ddg-vpo-text">${overlayCopy.subtitle}</div>
                <div class="ddg-vpo-buttons">
                    <button class="ddg-vpo-button ddg-vpo-cancel" type="button">${overlayCopy.buttonOptOut}</button>
                    <a class="ddg-vpo-button ddg-vpo-open" href="#">${overlayCopy.buttonOpen}</a>
                </div>
                <div class="ddg-vpo-remember">
                    <label for="remember"> <input id="remember" type="checkbox" name="ddg-remember" /> ${overlayCopy.rememberLabel} </label>
                </div>
            </div>
        `.toString();

        overlayElement.innerHTML = this.policy.createHTML(safeString);

        /**
         * Set the link
         * @type {string}
         */
        const href = this.params.toPrivatePlayerUrl();
        overlayElement.querySelector('.ddg-vpo-open')?.setAttribute('href', href);

        /**
         * Add thumbnail
         */
        this.appendThumbnail(overlayElement, this.params.id);

        /**
         * Setup the click handlers
         */
        this.setupButtonsInsideOverlay(overlayElement, this.params);

        return overlayElement;
    }

    /**
     * @param {HTMLElement} overlayElement
     * @param {string} videoId
     */
    appendThumbnail(overlayElement, videoId) {
        const imageUrl = this.environment.getLargeThumbnailSrc(videoId);
        appendImageAsBackground(overlayElement, '.ddg-vpo-bg', imageUrl);
    }

    /**
     * @param {HTMLElement} containerElement
     * @param {import("../util").VideoParams} params
     */
    setupButtonsInsideOverlay(containerElement, params) {
        const cancelElement = containerElement.querySelector('.ddg-vpo-cancel');
        const watchInPlayer = containerElement.querySelector('.ddg-vpo-open');
        if (!cancelElement) return console.warn('Could not access .ddg-vpo-cancel');
        if (!watchInPlayer) return console.warn('Could not access .ddg-vpo-open');
        const optOutHandler = (e) => {
            if (e.isTrusted) {
                const remember = containerElement.querySelector('input[name="ddg-remember"]');
                if (!(remember instanceof HTMLInputElement)) throw new Error('cannot find our input');
                this.manager.userOptOut(remember.checked, params);
            }
        };
        const watchInPlayerHandler = (e) => {
            if (e.isTrusted) {
                e.preventDefault();
                const remember = containerElement.querySelector('input[name="ddg-remember"]');
                if (!(remember instanceof HTMLInputElement)) throw new Error('cannot find our input');
                this.manager.userOptIn(remember.checked, params);
            }
        };
        cancelElement.addEventListener('click', optOutHandler);
        watchInPlayer.addEventListener('click', watchInPlayerHandler);
    }
}
