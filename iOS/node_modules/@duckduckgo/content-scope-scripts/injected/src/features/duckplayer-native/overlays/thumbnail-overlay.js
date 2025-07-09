import css from './thumbnail-overlay.css';
import { createPolicy, html } from '../../../dom-utils.js';
import { customElementsDefine, customElementsGet } from '../../../captured-globals.js';
import { VideoParams, appendImageAsBackground, Logger } from '../../duckplayer/util.js';

/**
 * The custom element that we use to present our UI elements
 * over the YouTube player
 */
export class DDGVideoThumbnailOverlay extends HTMLElement {
    static CUSTOM_TAG_NAME = 'ddg-video-thumbnail-overlay-mobile';
    static OVERLAY_CLICKED = 'overlay-clicked';

    policy = createPolicy();
    /** @type {Logger} */
    logger;
    /** @type {boolean} */
    testMode = false;
    /** @type {HTMLElement} */
    container;
    /** @type {string} */
    href;

    static register() {
        if (!customElementsGet(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)) {
            customElementsDefine(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME, DDGVideoThumbnailOverlay);
        }
    }

    connectedCallback() {
        this.createMarkupAndStyles();
    }

    createMarkupAndStyles() {
        const shadow = this.attachShadow({ mode: this.testMode ? 'open' : 'closed' });

        const style = document.createElement('style');
        style.innerText = css;

        const container = document.createElement('div');
        container.classList.add('wrapper');
        const content = this.render();
        container.innerHTML = this.policy.createHTML(content);
        shadow.append(style, container);
        this.container = container;

        // Add click event listener to the overlay
        const overlay = container.querySelector('.ddg-video-player-overlay');
        if (overlay) {
            overlay.addEventListener('click', () => {
                this.dispatchEvent(new Event(DDGVideoThumbnailOverlay.OVERLAY_CLICKED));
            });
        }

        this.logger?.log('Created', DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME, 'with container', container);
        this.appendThumbnail();
    }

    appendThumbnail() {
        const params = VideoParams.forWatchPage(this.href);
        const imageUrl = params?.toLargeThumbnailUrl();

        if (!imageUrl) {
            this.logger?.warn('Could not get thumbnail url for video id', params?.id);
            return;
        }

        if (this.testMode) {
            this.logger?.log('Appending thumbnail', imageUrl);
        }
        appendImageAsBackground(this.container, '.ddg-vpo-bg', imageUrl);
    }

    /**
     * @returns {string}
     */
    render() {
        return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="logo"></div>
            </div>
        `.toString();
    }
}

/**
 *
 * @param {HTMLElement} targetElement
 * @param {import("../../duckplayer/environment").Environment} environment
 * @param {() => void} [onClick] Optional callback to be called when the overlay is clicked
 */
export function showThumbnailOverlay(targetElement, environment, onClick) {
    const logger = new Logger({
        id: 'THUMBNAIL_OVERLAY',
        shouldLog: () => environment.isTestMode(),
    });

    DDGVideoThumbnailOverlay.register();

    const overlay = /** @type {DDGVideoThumbnailOverlay} */ (document.createElement(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME));
    overlay.logger = logger;
    overlay.testMode = environment.isTestMode();
    overlay.href = environment.getPlayerPageHref();

    if (onClick) {
        overlay.addEventListener(DDGVideoThumbnailOverlay.OVERLAY_CLICKED, onClick);
    }

    targetElement.appendChild(overlay);

    return () => {
        document.querySelector(DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME)?.remove();
    };
}
