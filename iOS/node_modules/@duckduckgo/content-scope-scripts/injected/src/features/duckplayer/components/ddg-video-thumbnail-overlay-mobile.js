import mobilecss from '../assets/mobile-video-thumbnail-overlay.css';
import { createPolicy, html } from '../../../dom-utils.js';

/**
 * @typedef {ReturnType<import("../text").overlayCopyVariants>} TextVariants
 * @typedef {TextVariants[keyof TextVariants]} Text
 */

/**
 * The custom element that we use to present our UI elements
 * over the YouTube player
 */
export class DDGVideoThumbnailOverlay extends HTMLElement {
    static CUSTOM_TAG_NAME = 'ddg-video-thumbnail-overlay-mobile';

    policy = createPolicy();
    /** @type {boolean} */
    testMode = false;

    connectedCallback() {
        this.createMarkupAndStyles();
    }

    createMarkupAndStyles() {
        const shadow = this.attachShadow({ mode: this.testMode ? 'open' : 'closed' });
        const style = document.createElement('style');
        style.innerText = mobilecss;
        const container = document.createElement('div');
        const content = this.mobileHtml();
        container.innerHTML = this.policy.createHTML(content);
        shadow.append(style, container);
        this.container = container;
    }

    /**
     * @returns {string}
     */
    mobileHtml() {
        return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="logo"></div>
            </div>
        `.toString();
    }
}
