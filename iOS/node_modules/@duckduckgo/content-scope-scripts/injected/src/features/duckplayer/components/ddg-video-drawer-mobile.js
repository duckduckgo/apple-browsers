import mobilecss from '../assets/mobile-video-drawer.css';
import dax from '../assets/dax.svg';
import info from '../assets/info-solid.svg';
import { createPolicy, html, trustedUnsafe } from '../../../dom-utils.js';
import { DDGVideoThumbnailOverlay } from './ddg-video-thumbnail-overlay-mobile';

/**
 * @typedef {ReturnType<import("../text").overlayCopyVariants>} TextVariants
 * @typedef {TextVariants[keyof TextVariants]} Text
 */

/**
 * The custom element that we use to present our UI elements
 * over the YouTube player
 */
export class DDGVideoDrawerMobile extends HTMLElement {
    static CUSTOM_TAG_NAME = 'ddg-video-drawer-mobile';
    static OPEN_INFO = 'open-info';
    static OPT_IN = 'opt-in';
    static OPT_OUT = 'opt-out';
    static DISMISS = 'dismiss';
    static THUMBNAIL_CLICK = 'thumbnail-click';
    static DID_EXIT = 'did-exit';

    policy = createPolicy();
    /** @type {boolean} */
    testMode = false;
    /** @type {Text | null} */
    text = null;
    /** @type {HTMLElement | null} */
    container;
    /** @type {HTMLElement | null} */
    drawer;
    /** @type {HTMLElement | null} */
    overlay;

    /** @type {'idle'|'animating'} */
    animationState = 'idle';

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
        this.animateOverlay('in');
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
            <div class="ddg-mobile-drawer-overlay">
                <div class="ddg-mobile-drawer-background"></div>
                <div class="ddg-mobile-drawer">
                    <div class="heading">
                        <div class="logo">${svgIcon}</div>
                        <div class="title">${this.text.title}</div>
                        <div class="info">
                            <button class="info-button" type="button" aria-label="Open Information Modal">${infoIcon}</button>
                        </div>
                    </div>
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
     *
     * @param {'in'|'out'} direction
     */
    animateOverlay(direction) {
        if (!this.overlay) return;
        this.animationState = 'animating';

        switch (direction) {
            case 'in':
                this.overlay.classList.remove('animateOut');
                this.overlay.classList.add('animateIn');
                break;
            case 'out':
                this.overlay.classList.remove('animateIn');
                this.overlay.classList.add('animateOut');
                break;
        }
    }

    /**
     * @param {() => void} callback
     */
    onAnimationEnd(callback) {
        if (this.animationState !== 'animating') callback();

        this.overlay?.addEventListener(
            'animationend',
            () => {
                callback();
            },
            { once: true },
        );
    }

    /**
     * @param {HTMLElement} [container]
     * @returns
     */
    setupEventHandlers(container) {
        if (!container) {
            console.warn('Error setting up drawer component');
            return;
        }

        const switchElem = container.querySelector('[role=switch]');
        const infoButton = container.querySelector('.info-button');
        const remember = container.querySelector('input[name="ddg-remember"]');
        const cancelElement = container.querySelector('.ddg-vpo-cancel');
        const watchInPlayer = container.querySelector('.ddg-vpo-open');
        const background = container.querySelector('.ddg-mobile-drawer-background');
        const overlay = container.querySelector('.ddg-mobile-drawer-overlay');
        const drawer = container.querySelector('.ddg-mobile-drawer');

        if (
            !cancelElement ||
            !watchInPlayer ||
            !switchElem ||
            !infoButton ||
            !background ||
            !overlay ||
            !drawer ||
            !(remember instanceof HTMLInputElement)
        ) {
            return console.warn('missing elements');
        }

        this.container = container;
        this.overlay = /** @type {HTMLElement} */ (overlay);
        this.drawer = /** @type {HTMLElement} */ (drawer);

        infoButton.addEventListener('click', () => {
            this.dispatchEvent(new Event(DDGVideoDrawerMobile.OPEN_INFO));
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
            this.animateOverlay('out');
            this.dispatchEvent(new CustomEvent(DDGVideoDrawerMobile.OPT_OUT, { detail: { remember: remember.checked } }));
        });

        background.addEventListener('click', (e) => {
            if (!e.isTrusted || e.target !== background) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            this.animateOverlay('out');

            const mouseEvent = /** @type {MouseEvent} */ (e);
            let eventName = DDGVideoDrawerMobile.DISMISS;
            for (const element of document.elementsFromPoint(mouseEvent.clientX, mouseEvent.clientY)) {
                if (element.tagName === DDGVideoThumbnailOverlay.CUSTOM_TAG_NAME.toUpperCase()) {
                    eventName = DDGVideoDrawerMobile.THUMBNAIL_CLICK;
                    break;
                }
            }

            this.dispatchEvent(new CustomEvent(eventName));
        });

        watchInPlayer.addEventListener('click', (e) => {
            if (!e.isTrusted) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            this.dispatchEvent(new CustomEvent(DDGVideoDrawerMobile.OPT_IN, { detail: { remember: remember.checked } }));
        });

        overlay.addEventListener('animationend', () => {
            this.animationState = 'idle';
        });
    }
}
