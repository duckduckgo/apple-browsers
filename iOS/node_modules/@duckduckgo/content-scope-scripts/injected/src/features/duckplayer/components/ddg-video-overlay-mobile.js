import mobilecss from '../assets/mobile-video-overlay.css';
import dax from '../assets/dax.svg';
import info from '../assets/info.svg';
import { createPolicy, html, trustedUnsafe } from '../../../dom-utils.js';

/**
 * @typedef {ReturnType<import("../text").overlayCopyVariants>} TextVariants
 * @typedef {TextVariants[keyof TextVariants]} Text
 */

/**
 * The custom element that we use to present our UI elements
 * over the YouTube player
 */
export class DDGVideoOverlayMobile extends HTMLElement {
    static CUSTOM_TAG_NAME = 'ddg-video-overlay-mobile';
    static OPEN_INFO = 'open-info';
    static OPT_IN = 'opt-in';
    static OPT_OUT = 'opt-out';

    policy = createPolicy();
    /** @type {boolean} */
    testMode = false;
    /** @type {Text | null} */
    text = null;

    connectedCallback() {
        this.createMarkupAndStyles();
    }

    createMarkupAndStyles() {
        const shadow = this.attachShadow({ mode: this.testMode ? 'open' : 'closed' });
        const style = document.createElement('style');
        style.innerText = mobilecss;
        const overlayElement = document.createElement('div');
        const content = this.mobileHtml();
        overlayElement.innerHTML = this.policy.createHTML(content);
        shadow.append(style, overlayElement);
        this.setupEventHandlers(overlayElement);
    }

    /**
     * @returns {string}
     */
    mobileHtml() {
        if (!this.text) {
            console.warn('missing `text`. Please assign before rendering');
            return '';
        }
        const svgIcon = trustedUnsafe(dax);
        const infoIcon = trustedUnsafe(info);
        return html`
            <div class="ddg-video-player-overlay">
                <div class="bg ddg-vpo-bg"></div>
                <div class="content ios">
                    <div class="logo">${svgIcon}</div>
                    <div class="title">${this.text.title}</div>
                    <div class="info">
                        <button class="button button--info" type="button" aria-label="Open Information Modal">${infoIcon}</button>
                    </div>
                    <div class="text">${this.text.subtitle}</div>
                    <div class="buttons">
                        <button class="button cancel ddg-vpo-cancel" type="button">${this.text.buttonOptOut}</button>
                        <a class="button open ddg-vpo-open" href="#">${this.text.buttonOpen}</a>
                    </div>
                    <div class="remember">
                        <div class="remember-label">
                            <span class="remember-text"> ${this.text.rememberLabel} </span>
                            <span class="remember-checkbox">
                                <input id="remember" type="checkbox" name="ddg-remember" hidden />
                                <button role="switch" aria-checked="false" class="switch ios-switch">
                                    <span class="thumb"></span>
                                </button>
                            </span>
                        </div>
                    </div>
                </div>
            </div>
        `.toString();
    }

    /**
     * @param {HTMLElement} containerElement
     */
    setupEventHandlers(containerElement) {
        const switchElem = containerElement.querySelector('[role=switch]');
        const infoButton = containerElement.querySelector('.button--info');
        const remember = containerElement.querySelector('input[name="ddg-remember"]');
        const cancelElement = containerElement.querySelector('.ddg-vpo-cancel');
        const watchInPlayer = containerElement.querySelector('.ddg-vpo-open');

        if (!infoButton || !cancelElement || !watchInPlayer || !switchElem || !(remember instanceof HTMLInputElement)) {
            return console.warn('missing elements');
        }

        infoButton.addEventListener('click', () => {
            this.dispatchEvent(new Event(DDGVideoOverlayMobile.OPEN_INFO));
        });

        switchElem.addEventListener('pointerdown', () => {
            const current = switchElem.getAttribute('aria-checked');
            if (current === 'false') {
                switchElem.setAttribute('aria-checked', 'true');
                remember.checked = true;
            } else {
                switchElem.setAttribute('aria-checked', 'false');
                remember.checked = false;
            }
        });

        cancelElement.addEventListener('click', (e) => {
            if (!e.isTrusted) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            this.dispatchEvent(new CustomEvent(DDGVideoOverlayMobile.OPT_OUT, { detail: { remember: remember.checked } }));
        });

        watchInPlayer.addEventListener('click', (e) => {
            if (!e.isTrusted) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            this.dispatchEvent(new CustomEvent(DDGVideoOverlayMobile.OPT_IN, { detail: { remember: remember.checked } }));
        });
    }
}
