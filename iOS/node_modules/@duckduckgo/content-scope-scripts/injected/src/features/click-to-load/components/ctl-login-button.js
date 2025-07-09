import { html } from '../../../dom-utils';
import cssVars from '../assets/shared.css';
import css from '../assets/ctl-login-button.css';
import { logoImg } from '../ctl-assets';

/**
 * @typedef LearnMoreParams - "Learn More" link params
 * @property {string} readAbout - "Learn More" aria-label text
 * @property {string} learnMore - "Learn More" link text
 */

/**
 * Template for creating a <div/> element placeholder for blocked login embedded buttons.
 * The constructor gets a list of parameters with the
 * content and event handlers for this template.
 * This is currently only used in our Mobile Apps, but can be expanded in the future.
 */
export class DDGCtlLoginButton {
    /**
     * Placeholder container element for blocked login button
     * @type {HTMLDivElement}
     */
    #element;

    /**
     * @param {object} params - Params for building a custom element with
     *                          a placeholder for a blocked login button
     * @param {boolean} params.devMode - Used to create the Shadow DOM on 'open'(true) or 'closed'(false) mode
     * @param {string} params.label - Button text
     * @param {string} params.logoIcon - Logo image to be displayed in the Login Button to the left of the label text
     * @param {string} params.hoverText - Text for popover on button hover
     * @param {boolean=} params.useSlimCard - Flag for using less padding on card (ie YT CTL on mobile)
     * @param {HTMLElement} params.originalElement - The original element this placeholder is replacing.
     * @param {LearnMoreParams} params.learnMore - Localized strings for "Learn More" link.
     * @param {(originalElement: HTMLIFrameElement | HTMLElement, replacementElement: HTMLElement) => (e: any) => void} params.onClick
     */
    constructor(params) {
        this.params = params;

        /**
         * Create the placeholder element to be inject in the page
         * @type {HTMLDivElement}
         */
        this.element = document.createElement('div');

        /**
         * Create the shadow root, closed to prevent any outside observers
         * @type {ShadowRoot}
         */
        const shadow = this.element.attachShadow({
            mode: this.params.devMode ? 'open' : 'closed',
        });

        /**
         * Add our styles
         * @type {HTMLStyleElement}
         */
        const style = document.createElement('style');
        style.innerText = cssVars + css;

        /**
         * Create the Facebook login button
         * @type {HTMLDivElement}
         */
        const loginButton = this._createLoginButton();

        /**
         * Setup the click handlers
         */
        this._setupEventListeners(loginButton);

        /**
         * Append both to the shadow root
         */
        shadow.appendChild(loginButton);
        shadow.appendChild(style);
    }

    /**
     * @returns {HTMLDivElement}
     */
    get element() {
        return this.#element;
    }

    /**
     * @param {HTMLDivElement} el - New placeholder element
     */
    set element(el) {
        this.#element = el;
    }

    /**
     * Creates a placeholder Facebook login button. When clicked, a warning dialog
     * is displayed to the user. The login flow only continues if the user clicks to
     * proceed.
     * @returns {HTMLDivElement}
     */
    _createLoginButton() {
        const { label, hoverText, logoIcon, learnMore } = this.params;

        const { popoverStyle, arrowStyle } = this._calculatePopoverPosition();

        const container = document.createElement('div');
        // Add our own styles and inherit any local class styles on the button
        container.classList.add('ddg-fb-login-container');

        container.innerHTML = html`
            <div id="DuckDuckGoPrivacyEssentialsHoverable">
                <!-- Login Button -->
                <button class="DuckDuckGoButton tertiary ddg-ctl-fb-login-btn">
                    <img class="ddg-ctl-button-login-icon" height="20px" width="20px" src="${logoIcon}" />
                    <div>${label}</div>
                </button>

                <!-- Popover - hover box -->
                <div id="DuckDuckGoPrivacyEssentialsHoverableText" class="ddg-popover" style="${popoverStyle}">
                    <div class="ddg-popover-arrow" style="${arrowStyle}"></div>

                    <div class="ddg-title-header">
                        <div class="ddg-logo">
                            <img class="ddg-logo-img" src="${logoImg}" height="21px" />
                        </div>
                        <div id="DuckDuckGoPrivacyEssentialsCTLElementTitle" class="ddg-title-text">DuckDuckGo</div>
                    </div>

                    <div class="ddg-popover-body">
                        ${hoverText}
                        <a
                            class="ddg-text-link"
                            aria-label="${learnMore.readAbout}"
                            href="https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/"
                            target="_blank"
                            id="learnMoreLink"
                        >
                            ${learnMore.learnMore}
                        </a>
                    </div>
                </div>
            </div>
        `.toString();

        return container;
    }

    /**
     * The left side of the popover may go offscreen if the
     * login button is all the way on the left side of the page. This
     * If that is the case, dynamically shift the box right so it shows
     * properly.
     * @returns {{
     *  popoverStyle: string, // CSS styles to be applied in the Popover container
     *  arrowStyle: string,   // CSS styles to be applied in the Popover arrow
     * }}
     */
    _calculatePopoverPosition() {
        const { originalElement } = this.params;
        const rect = originalElement.getBoundingClientRect();
        const textBubbleWidth = 360; // Should match the width rule in .ddg-popover
        const textBubbleLeftShift = 100; // Should match the CSS left: rule in .ddg-popover
        const arrowDefaultLocationPercent = 50;

        let popoverStyle;
        let arrowStyle;

        if (rect.left < textBubbleLeftShift) {
            const leftShift = -rect.left + 10; // 10px away from edge of the screen
            popoverStyle = `left: ${leftShift}px;`;
            const change = (1 - rect.left / textBubbleLeftShift) * (100 - arrowDefaultLocationPercent);
            arrowStyle = `left: ${Math.max(10, arrowDefaultLocationPercent - change)}%;`;
        } else if (rect.left + textBubbleWidth - textBubbleLeftShift > window.innerWidth) {
            const rightShift = rect.left + textBubbleWidth - textBubbleLeftShift;
            const diff = Math.min(rightShift - window.innerWidth, textBubbleLeftShift);
            const rightMargin = 20; // Add some margin to the page, so scrollbar doesn't overlap.
            popoverStyle = `left: -${textBubbleLeftShift + diff + rightMargin}px;`;
            const change = (diff / textBubbleLeftShift) * (100 - arrowDefaultLocationPercent);
            arrowStyle = `left: ${Math.max(10, arrowDefaultLocationPercent + change)}%;`;
        } else {
            popoverStyle = `left: -${textBubbleLeftShift}px;`;
            arrowStyle = `left: ${arrowDefaultLocationPercent}%;`;
        }

        return { popoverStyle, arrowStyle };
    }

    /**
     *
     * @param {HTMLElement} loginButton
     */
    _setupEventListeners(loginButton) {
        const { originalElement, onClick } = this.params;

        loginButton.querySelector('.ddg-ctl-fb-login-btn')?.addEventListener('click', onClick(originalElement, this.element));
    }
}
