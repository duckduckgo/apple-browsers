import { html } from '../../../dom-utils';
import cssVars from '../assets/shared.css';
import css from '../assets/ctl-placeholder-block.css';
import { logoImg as daxImg } from '../ctl-assets';

/**
 * Size keys for a placeholder
 * @typedef { 'size-xs' | 'size-sm' | 'size-md' | 'size-lg'| null } placeholderSize
 */

/**
 * @typedef WithToggleParams - Toggle params
 * @property {boolean} isActive - Toggle state
 * @property {string} dataKey - data-key attribute for toggle button
 * @property {string} label - Text to be presented with toggle
 * @property {'md' | 'lg'} [size=md] - Toggle size variant, 'md' by default
 * @property {() => void} onClick - Toggle on click callback
 */
/**
 * @typedef WithFeedbackParams - Feedback link params
 * @property {string=} label - "Share Feedback" link text
 * @property {() => void} onClick - Feedback element on click callback
 */
/**
 * @typedef LearnMoreParams - "Learn More" link params
 * @property {string} readAbout - "Learn More" aria-label text
 * @property {string} learnMore - "Learn More" link text
 */

/**
 * The custom HTML element (Web Component) template with the placeholder for blocked
 * embedded content. The constructor gets a list of parameters with the
 * content and event handlers for this template.
 * This is currently only used in our Mobile Apps, but can be expanded in the future.
 */
export class DDGCtlPlaceholderBlockedElement extends HTMLElement {
    static CUSTOM_TAG_NAME = 'ddg-ctl-placeholder-blocked';
    /**
     * Min height that the placeholder needs to have in order to
     * have enough room to display content.
     */
    static MIN_CONTENT_HEIGHT = 110;
    static MAX_CONTENT_WIDTH_SMALL = 480;
    static MAX_CONTENT_WIDTH_MEDIUM = 650;
    /**
     * Set observed attributes that will trigger attributeChangedCallback()
     */
    static get observedAttributes() {
        return ['style'];
    }

    /**
     * Placeholder element for blocked content
     * @type {HTMLDivElement}
     */
    placeholderBlocked;

    /**
     * Size variant of the latest calculated size of the placeholder.
     * This is used to add the appropriate CSS class to the placeholder container
     * and adapt the layout for each size.
     * @type {placeholderSize}
     */
    size = null;

    /**
     * @param {object} params - Params for building a custom element
     *                          with a placeholder for blocked content
     * @param {boolean} params.devMode - Used to create the Shadow DOM on 'open'(true) or 'closed'(false) mode
     * @param {string} params.title - Card title text
     * @param {string} params.body - Card body text
     * @param {string} params.unblockBtnText - Unblock button text
     * @param {boolean=} params.useSlimCard - Flag for using less padding on card (ie YT CTL on mobile)
     * @param {HTMLElement} params.originalElement - The original element this placeholder is replacing.
     * @param {LearnMoreParams} params.learnMore - Localized strings for "Learn More" link.
     * @param {WithToggleParams=} params.withToggle - Toggle config to be displayed in the bottom of the placeholder
     * @param {WithFeedbackParams=} params.withFeedback - Shows feedback link on tablet and desktop sizes,
     * @param {(originalElement: HTMLIFrameElement | HTMLElement, replacementElement: HTMLElement) => (e: any) => void} params.onButtonClick
     */
    constructor(params) {
        super();
        this.params = params;
        /**
         * Create the shadow root, closed to prevent any outside observers
         * @type {ShadowRoot}
         */
        const shadow = this.attachShadow({
            mode: this.params.devMode ? 'open' : 'closed',
        });

        /**
         * Add our styles
         * @type {HTMLStyleElement}
         */
        const style = document.createElement('style');
        style.innerText = cssVars + css;

        /**
         * Creates the placeholder for blocked content
         * @type {HTMLDivElement}
         */
        this.placeholderBlocked = this.createPlaceholder();
        /**
         * Creates the Share Feedback element
         * @type {HTMLDivElement | null}
         */
        const feedbackLink = this.params.withFeedback ? this.createShareFeedbackLink() : null;
        /**
         * Setup the click handlers
         */
        this.setupEventListeners(this.placeholderBlocked, feedbackLink);

        /**
         * Append both to the shadow root
         */
        // eslint-disable-next-line @typescript-eslint/no-unused-expressions
        feedbackLink && this.placeholderBlocked.appendChild(feedbackLink);
        shadow.appendChild(this.placeholderBlocked);
        shadow.appendChild(style);
    }

    /**
     * Creates a placeholder for content blocked by Click to Load.
     * Note: We're using arrow functions () => {} in this class due to a bug
     * found in Firefox where it is getting the wrong "this" context on calls in the constructor.
     * This is a temporary workaround.
     * @returns {HTMLDivElement}
     */
    createPlaceholder = () => {
        const { title, body, unblockBtnText, useSlimCard, withToggle, withFeedback } = this.params;

        const container = document.createElement('div');
        container.classList.add('DuckDuckGoSocialContainer');
        const cardClassNames = [
            ['slim-card', !!useSlimCard],
            ['with-feedback-link', !!withFeedback],
        ]
            .map(([className, active]) => (active ? className : ''))
            .join(' ');

        // Only add a card footer if we have the toggle button to display
        const cardFooterSection = withToggle ? html`<div class="ddg-ctl-placeholder-card-footer">${this.createToggleButton()}</div> ` : '';
        const learnMoreLink = this.createLearnMoreLink();

        container.innerHTML = html`
            <div class="ddg-ctl-placeholder-card ${cardClassNames}">
                <div class="ddg-ctl-placeholder-card-header">
                    <img class="ddg-ctl-placeholder-card-header-dax" src=${daxImg} alt="DuckDuckGo Dax" />
                    <div class="ddg-ctl-placeholder-card-title">${title}. ${learnMoreLink}</div>
                </div>
                <div class="ddg-ctl-placeholder-card-body">
                    <div class="ddg-ctl-placeholder-card-body-text">${body} ${learnMoreLink}</div>
                    <button class="DuckDuckGoButton tertiary ddg-ctl-unblock-btn" type="button">
                        <div>${unblockBtnText}</div>
                    </button>
                </div>
                ${cardFooterSection}
            </div>
        `.toString();

        return container;
    };

    /**
     * Creates a template string for Learn More link.
     */
    createLearnMoreLink = () => {
        const { learnMore } = this.params;

        return html`<a
            class="ddg-text-link ddg-learn-more"
            aria-label="${learnMore.readAbout}"
            href="https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/"
            target="_blank"
            >${learnMore.learnMore}</a
        >`;
    };

    /**
     * Creates a Feedback Link container row
     * @returns {HTMLDivElement}
     */
    createShareFeedbackLink = () => {
        const { withFeedback } = this.params;

        const container = document.createElement('div');
        container.classList.add('ddg-ctl-feedback-row');

        container.innerHTML = html`
            <button class="ddg-ctl-feedback-link" type="button">${withFeedback?.label || 'Share Feedback'}</button>
        `.toString();

        return container;
    };

    /**
     * Creates a template string for a toggle button with text.
     */
    createToggleButton = () => {
        const { withToggle } = this.params;
        if (!withToggle) return;

        const { isActive, dataKey, label, size: toggleSize = 'md' } = withToggle;

        const toggleButton = html`
            <div class="ddg-toggle-button-container">
                <button
                    class="ddg-toggle-button ${isActive ? 'active' : 'inactive'} ${toggleSize}"
                    type="button"
                    aria-pressed=${!!isActive}
                    data-key=${dataKey}
                >
                    <div class="ddg-toggle-button-bg"></div>
                    <div class="ddg-toggle-button-knob"></div>
                </button>
                <div class="ddg-toggle-button-label">${label}</div>
            </div>
        `;
        return toggleButton;
    };

    /**
     *
     * @param {HTMLElement} containerElement
     * @param {HTMLElement?} feedbackLink
     */
    setupEventListeners = (containerElement, feedbackLink) => {
        const { withToggle, withFeedback, originalElement, onButtonClick } = this.params;

        containerElement.querySelector('button.ddg-ctl-unblock-btn')?.addEventListener('click', onButtonClick(originalElement, this));

        if (withToggle) {
            containerElement.querySelector('.ddg-toggle-button-container')?.addEventListener('click', withToggle.onClick);
        }
        if (withFeedback && feedbackLink) {
            feedbackLink.querySelector('.ddg-ctl-feedback-link')?.addEventListener('click', withFeedback.onClick);
        }
    };

    /**
     * Use JS to calculate the width and height of the root element placeholder. We could use a CSS Container Query, but full
     * support to it was only added recently, so we're not using it for now.
     * https://caniuse.com/css-container-queries
     */
    updatePlaceholderSize = () => {
        /** @type {placeholderSize} */
        let newSize = null;

        const { height, width } = this.getBoundingClientRect();
        if (height && height < DDGCtlPlaceholderBlockedElement.MIN_CONTENT_HEIGHT) {
            newSize = 'size-xs';
        } else if (width) {
            if (width < DDGCtlPlaceholderBlockedElement.MAX_CONTENT_WIDTH_SMALL) {
                newSize = 'size-sm';
            } else if (width < DDGCtlPlaceholderBlockedElement.MAX_CONTENT_WIDTH_MEDIUM) {
                newSize = 'size-md';
            } else {
                newSize = 'size-lg';
            }
        }

        if (newSize && newSize !== this.size) {
            if (this.size) {
                this.placeholderBlocked.classList.remove(this.size);
            }
            this.placeholderBlocked.classList.add(newSize);
            this.size = newSize;
        }
    };

    /**
     * Web Component lifecycle function.
     * When element is first added to the DOM, trigger this callback and
     * update the element CSS size class.
     */
    connectedCallback() {
        this.updatePlaceholderSize();
    }

    /**
     * Web Component lifecycle function.
     * When the root element gets the 'style' attribute updated, reflect that in the container
     * element inside the shadow root. This way, we can copy the size and other styles from the root
     * element and have the inner context be able to use the same sizes to adapt the template layout.
     * @param {string} attr Observed attribute key
     * @param {*} _ Attribute old value, ignored
     * @param {*} newValue Attribute new value
     */
    attributeChangedCallback(attr, _, newValue) {
        if (attr === 'style') {
            this.placeholderBlocked[attr].cssText = newValue;
            this.updatePlaceholderSize();
        }
    }
}
