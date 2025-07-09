import { Messaging, TestTransportConfig, WebkitMessagingConfig } from '../../../messaging/index.js';
import { createCustomEvent, originalWindowDispatchEvent } from '../utils.js';
import { logoImg, loadingImages, closeIcon, facebookLogo } from './click-to-load/ctl-assets.js';
import { getStyles, getConfig } from './click-to-load/ctl-config.js';
import { SendMessageMessagingTransport } from '../sendmessage-transport.js';
import ContentFeature from '../content-feature.js';
import { DDGCtlPlaceholderBlockedElement } from './click-to-load/components/ctl-placeholder-blocked.js';
import { DDGCtlLoginButton } from './click-to-load/components/ctl-login-button.js';
import { registerCustomElements } from './click-to-load/components';

/**
 * @typedef {'darkMode' | 'lightMode' | 'loginMode' | 'cancelMode'} displayMode
 *   Key for theme value to determine the styling of buttons/placeholders.
 *   Matches `styles[mode]` keys:
 *     - `'lightMode'`: Primary colors styling for light theme
 *     - `'darkMode'`: Primary colors styling for dark theme
 *     - `'cancelMode'`: Secondary colors styling for all themes
 */

let devMode = false;
let isYoutubePreviewsEnabled = false;
let appID;

const titleID = 'DuckDuckGoPrivacyEssentialsCTLElementTitle';

// Configuration for how the placeholder elements should look and behave.
// @see {getConfig}
let config = null;
let sharedStrings = null;
let styles = null;

/**
 * List of platforms where we can skip showing a Web Modal from C-S-S.
 * It is generally expected that the platform will show a native modal instead.
 * @type {import('../utils').Platform["name"][]} */
const platformsWithNativeModalSupport = ['android', 'ios'];
/**
 * Platforms supporting the new layout using Web Components.
 * @type {import('../utils').Platform["name"][]} */
const platformsWithWebComponentsEnabled = ['android', 'ios'];
/**
 * Based on the current Platform where the Widget is running, it will
 * return if it is one of our mobile apps or not. This should be used to
 * define which layout to use between Mobile and Desktop Platforms variations.
 * @type {import('../utils').Platform["name"][]} */
const mobilePlatforms = ['android', 'ios'];

// TODO: Remove these redundant data structures and refactor the related code.
//       There should be no need to have the entity configuration stored in two
//       places.
const entities = [];
const entityData = {};

// Used to avoid displaying placeholders for the same tracking element twice.
const knownTrackingElements = new WeakSet();

// Promise that is resolved when the Click to Load feature init() function has
// finished its work, enough that it's now safe to replace elements with
// placeholders.
let readyToDisplayPlaceholdersResolver;
const readyToDisplayPlaceholders = new Promise((resolve) => {
    readyToDisplayPlaceholdersResolver = resolve;
});

// Promise that is resolved when the page has finished loading (and
// readyToDisplayPlaceholders has resolved). Wait for this before sending
// essential messages to surrogate scripts.
let afterPageLoadResolver;
const afterPageLoad = new Promise((resolve) => {
    afterPageLoadResolver = resolve;
});

// Messaging layer for Click to Load. The messaging instance is initialized in
// ClickToLoad.init() and updated here to be used outside ClickToLoad class
// we need a module scoped reference.
/** @type {import("@duckduckgo/messaging").Messaging} */
let _messagingModuleScope;
/** @type function */
let _addDebugFlag;
const ctl = {
    /**
     * @return {import("@duckduckgo/messaging").Messaging}
     */
    get messaging() {
        if (!_messagingModuleScope) throw new Error('Messaging not initialized');
        return _messagingModuleScope;
    },

    addDebugFlag() {
        if (!_addDebugFlag) throw new Error('addDebugFlag not initialized');
        return _addDebugFlag();
    },
};

/*********************************************************
 *  Widget Replacement logic
 *********************************************************/
class DuckWidget {
    /**
     * @param {Object} widgetData
     *   The configuration for this "widget" as determined in ctl-config.js.
     * @param {HTMLElement} originalElement
     *   The original tracking element to replace with a placeholder.
     * @param {string} entity
     *   The entity behind the tracking element (e.g. "Facebook, Inc.").
     * @param {import('../utils').Platform} platform
     *   The platform where Click to Load and the Duck Widget is running on (ie Extension, Android App, etc)
     */
    constructor(widgetData, originalElement, entity, platform) {
        this.clickAction = { ...widgetData.clickAction }; // shallow copy
        this.replaceSettings = widgetData.replaceSettings;
        this.originalElement = originalElement;
        this.placeholderElement = null;
        this.dataElements = {};
        this.gatherDataElements();
        this.entity = entity;
        this.widgetID = Math.random();
        this.autoplay = false;
        // Boolean if widget is unblocked and content should not be blocked
        this.isUnblocked = false;
        this.platform = platform;
    }

    /**
     * Dispatch an event on the target element, including the widget's ID and
     * other details.
     * @param {EventTarget} eventTarget
     * @param {string} eventName
     */
    dispatchEvent(eventTarget, eventName) {
        eventTarget.dispatchEvent(
            createCustomEvent(eventName, {
                detail: {
                    entity: this.entity,
                    replaceSettings: this.replaceSettings,
                    widgetID: this.widgetID,
                },
            }),
        );
    }

    /**
     * Take note of some of the tracking element's attributes (as determined by
     * clickAction.urlDataAttributesToPreserve) and store those in
     * this.dataElement.
     */
    gatherDataElements() {
        if (!this.clickAction.urlDataAttributesToPreserve) {
            return;
        }
        for (const [attrName, attrSettings] of Object.entries(this.clickAction.urlDataAttributesToPreserve)) {
            let value = this.originalElement.getAttribute(attrName);
            if (!value) {
                if (attrSettings.required) {
                    // Missing a required attribute means we won't be able to replace it
                    // with a light version, replace with full version.
                    this.clickAction.type = 'allowFull';
                }

                // If the attribute is "width", try first to measure the parent's width and use that as a default value.
                if (attrName === 'data-width') {
                    const windowWidth = window.innerWidth;
                    const { parentElement } = this.originalElement;
                    const parentStyles = parentElement ? window.getComputedStyle(parentElement) : null;
                    let parentInnerWidth = null;

                    // We want to calculate the inner width of the parent element as the iframe, when added back,
                    // should not be bigger than the space available in the parent element. There is no straightforward way of
                    // doing this. We need to get the parent's .clientWidth and remove the paddings size from it.
                    if (parentElement && parentStyles && parentStyles.display !== 'inline') {
                        parentInnerWidth =
                            parentElement.clientWidth - parseFloat(parentStyles.paddingLeft) - parseFloat(parentStyles.paddingRight);
                    }

                    if (parentInnerWidth && parentInnerWidth < windowWidth) {
                        value = parentInnerWidth.toString();
                    } else {
                        // Our default value for width is often greater than the window size of smaller
                        // screens (ie mobile). Then use whatever is the smallest value.
                        value = Math.min(attrSettings.default, windowWidth).toString();
                    }
                } else {
                    value = attrSettings.default;
                }
            }
            this.dataElements[attrName] = value;
        }
    }

    /**
     * Return the URL of the Facebook content, for use when a Facebook Click to
     * Load placeholder has been clicked by the user.
     * @returns {string}
     */
    getTargetURL() {
        // Copying over data fields should be done lazily, since some required data may not be
        // captured until after page scripts run.
        this.copySocialDataFields();
        return this.clickAction.targetURL;
    }

    /**
     * Determines which display mode the placeholder element should render in.
     * @returns {displayMode}
     */
    getMode() {
        // Login buttons are always the login style types
        if (this.replaceSettings.type === 'loginButton') {
            return 'loginMode';
        }
        if (window?.matchMedia('(prefers-color-scheme: dark)')?.matches) {
            return 'darkMode';
        }
        return 'lightMode';
    }

    /**
     * Take note of some of the tracking element's style attributes (as
     * determined by clickAction.styleDataAttributes) as a CSS string.
     *
     * @returns {string}
     */
    getStyle() {
        let styleString = 'border: none;';

        if (this.clickAction.styleDataAttributes) {
            // Copy elements from the original div into style attributes as directed by config
            for (const [attr, valAttr] of Object.entries(this.clickAction.styleDataAttributes)) {
                let valueFound = this.dataElements[valAttr.name];
                if (!valueFound) {
                    valueFound = this.dataElements[valAttr.fallbackAttribute];
                }
                let partialStyleString = '';
                if (valueFound) {
                    partialStyleString += `${attr}: ${valueFound}`;
                }
                if (!partialStyleString.includes(valAttr.unit)) {
                    partialStyleString += valAttr.unit;
                }
                partialStyleString += ';';
                styleString += partialStyleString;
            }
        }

        return styleString;
    }

    /**
     * Store some attributes from the original tracking element, used for both
     * placeholder element styling, and when restoring the original tracking
     * element.
     */
    copySocialDataFields() {
        if (!this.clickAction.urlDataAttributesToPreserve) {
            return;
        }

        // App ID may be set by client scripts, and is required for some elements.
        if (this.dataElements.app_id_replace && appID != null) {
            this.clickAction.targetURL = this.clickAction.targetURL.replace('app_id_replace', appID);
        }

        for (const key of Object.keys(this.dataElements)) {
            let attrValue = this.dataElements[key];

            if (!attrValue) {
                continue;
            }

            // The URL for Facebook videos are specified as the data-href
            // attribute on a div, that is then used to create the iframe.
            // Some websites omit the protocol part of the URL when doing
            // that, which then prevents the iframe from loading correctly.
            if (key === 'data-href' && attrValue.startsWith('//')) {
                attrValue = window.location.protocol + attrValue;
            }

            this.clickAction.targetURL = this.clickAction.targetURL.replace(key, encodeURIComponent(attrValue));
        }
    }

    /**
     * Creates an iFrame for this facebook content.
     *
     * @returns {HTMLIFrameElement}
     */
    createFBIFrame() {
        const frame = document.createElement('iframe');

        frame.setAttribute('src', this.getTargetURL());
        frame.setAttribute('style', this.getStyle());

        return frame;
    }

    /**
     * Tweaks an embedded YouTube video element ready for when it's
     * reloaded.
     *
     * @param {HTMLIFrameElement} videoElement
     * @returns {EventListener?} onError
     *   Function to be called if the video fails to load.
     */
    adjustYouTubeVideoElement(videoElement) {
        let onError = null;

        if (!videoElement.src) {
            return onError;
        }
        const url = new URL(videoElement.src);
        const { hostname: originalHostname } = url;

        // Upgrade video to YouTube's "privacy enhanced" mode, but fall back
        // to standard mode if the video fails to load.
        // Note:
        //  1. Changing the iframe's host like this won't cause a CSP
        //     violation on Chrome, see https://crbug.com/1271196.
        //  2. The onError event doesn't fire for blocked iframes on Chrome.
        if (originalHostname !== 'www.youtube-nocookie.com') {
            url.hostname = 'www.youtube-nocookie.com';
            onError = (event) => {
                url.hostname = originalHostname;
                videoElement.src = url.href;
                event.stopImmediatePropagation();
            };
        }

        // Configure auto-play correctly depending on if the video's preview
        // loaded, otherwise it doesn't allow autoplay.
        let allowString = videoElement.getAttribute('allow') || '';
        const allowed = new Set(allowString.split(';').map((s) => s.trim()));
        if (this.autoplay) {
            allowed.add('autoplay');
            url.searchParams.set('autoplay', '1');
        } else {
            allowed.delete('autoplay');
            url.searchParams.delete('autoplay');
        }
        allowString = Array.from(allowed).join('; ');
        videoElement.setAttribute('allow', allowString);

        videoElement.src = url.href;
        return onError;
    }

    /**
     * Fades the given element in/out.
     * @param {HTMLElement} element
     *   The element to fade in or out.
     * @param {number} interval
     *   Frequency of opacity updates (ms).
     * @param {boolean} fadeIn
     *   True if the element should fade in instead of out.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade in/out is complete.
     */
    fadeElement(element, interval, fadeIn) {
        return new Promise((resolve) => {
            let opacity = fadeIn ? 0 : 1;
            const originStyle = element.style.cssText;
            const fadeOut = setInterval(function () {
                opacity += fadeIn ? 0.03 : -0.03;
                element.style.cssText = originStyle + `opacity: ${opacity};`;
                if (opacity <= 0 || opacity >= 1) {
                    clearInterval(fadeOut);
                    resolve();
                }
            }, interval);
        });
    }

    /**
     * Fades the given element out.
     * @param {HTMLElement} element
     *   The element to fade out.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade out is complete.
     */
    fadeOutElement(element) {
        return this.fadeElement(element, 10, false);
    }

    /**
     * Fades the given element in.
     * @param {HTMLElement} element
     *   The element to fade in.
     * @returns {Promise<void>}
     *    Promise that resolves when the fade in is complete.
     */
    fadeInElement(element) {
        return this.fadeElement(element, 10, true);
    }

    /**
     * The function that's called when the user clicks to load some content.
     * Unblocks the content, puts it back in the page, and removes the
     * placeholder.
     * @param {HTMLIFrameElement} originalElement
     *   The original tracking element.
     * @param {HTMLElement} replacementElement
     *   The placeholder element.
     */
    clickFunction(originalElement, replacementElement) {
        let clicked = false;
        const handleClick = (e) => {
            // Ensure that the click is created by a user event & prevent double clicks from adding more animations
            if (e.isTrusted && !clicked) {
                e.stopPropagation();
                this.isUnblocked = true;
                clicked = true;
                let isLogin = false;
                // Logins triggered by user click means they were not triggered by the surrogate
                const isSurrogateLogin = false;
                const clickElement = e.srcElement; // Object.assign({}, e)
                if (this.replaceSettings.type === 'loginButton') {
                    isLogin = true;
                }
                const action = this.entity === 'Youtube' ? 'block-ctl-yt' : 'block-ctl-fb';
                // eslint-disable-next-line promise/prefer-await-to-then
                unblockClickToLoadContent({ entity: this.entity, action, isLogin, isSurrogateLogin }).then((response) => {
                    // If user rejected confirmation modal and content was not unblocked, inform surrogate and stop.
                    if (response && response.type === 'ddg-ctp-user-cancel') {
                        return abortSurrogateConfirmation(this.entity);
                    }

                    const parent = replacementElement.parentNode;

                    // The placeholder was removed from the DOM while we loaded
                    // the original content, give up.
                    if (!parent) return;

                    // If we allow everything when this element is clicked,
                    // notify surrogate to enable SDK and replace original element.
                    if (this.clickAction.type === 'allowFull') {
                        parent.replaceChild(originalElement, replacementElement);
                        this.dispatchEvent(window, 'ddg-ctp-load-sdk');
                        return;
                    }
                    // Create a container for the new FB element
                    const fbContainer = document.createElement('div');
                    fbContainer.style.cssText = styles.wrapperDiv;
                    const fadeIn = document.createElement('div');
                    fadeIn.style.cssText = 'display: none; opacity: 0;';

                    // Loading animation (FB can take some time to load)
                    const loadingImg = document.createElement('img');
                    loadingImg.setAttribute('src', loadingImages[this.getMode()]);
                    loadingImg.setAttribute('height', '14px');
                    loadingImg.style.cssText = styles.loadingImg;

                    // Always add the animation to the button, regardless of click source
                    if (clickElement.nodeName === 'BUTTON') {
                        clickElement.firstElementChild.insertBefore(loadingImg, clickElement.firstElementChild.firstChild);
                    } else {
                        // try to find the button
                        let el = clickElement;
                        let button = null;
                        while (button === null && el !== null) {
                            button = el.querySelector('button');
                            el = el.parentElement;
                        }
                        if (button) {
                            button.firstElementChild.insertBefore(loadingImg, button.firstElementChild.firstChild);
                        }
                    }

                    fbContainer.appendChild(fadeIn);

                    let fbElement;
                    let onError = null;
                    switch (this.clickAction.type) {
                        case 'iFrame':
                            fbElement = this.createFBIFrame();
                            break;
                        case 'youtube-video':
                            onError = this.adjustYouTubeVideoElement(originalElement);
                            fbElement = originalElement;
                            break;
                        default:
                            fbElement = originalElement;
                            break;
                    }

                    // Modify the overlay to include a Facebook iFrame, which
                    // starts invisible. Once loaded, fade out and remove the
                    // overlay then fade in the Facebook content.
                    parent.replaceChild(fbContainer, replacementElement);
                    fbContainer.appendChild(replacementElement);
                    fadeIn.appendChild(fbElement);
                    fbElement.addEventListener(
                        'load',
                        async () => {
                            await this.fadeOutElement(replacementElement);
                            fbContainer.replaceWith(fbElement);
                            this.dispatchEvent(fbElement, 'ddg-ctp-placeholder-clicked');
                            await this.fadeInElement(fadeIn);
                            // Focus on new element for screen readers.
                            fbElement.focus();
                        },
                        { once: true },
                    );
                    // Note: This event only fires on Firefox, on Chrome the frame's
                    //       load event will always fire.
                    if (onError) {
                        fbElement.addEventListener('error', onError, { once: true });
                    }
                });
            }
        };
        // If this is a login button, show modal if needed
        if (this.replaceSettings.type === 'loginButton' && entityData[this.entity].shouldShowLoginModal) {
            return (e) => {
                // Even if the user cancels the login attempt, consider Facebook Click to
                // Load to have been active on the page if the user reports the page as broken.
                if (this.entity === 'Facebook, Inc.') {
                    notifyFacebookLogin();
                }

                handleUnblockConfirmation(this.platform.name, this.entity, handleClick, e);
            };
        }
        return handleClick;
    }

    /**
     * Based on the current Platform where the Widget is running, it will
     * return if the new layout using Web Components is supported or not.
     * @returns {boolean}
     */
    shouldUseCustomElement() {
        return platformsWithWebComponentsEnabled.includes(this.platform.name);
    }

    /**
     * Based on the current Platform where the Widget is running, it will
     * return if it is one of our mobile apps or not. This should be used to
     * define which layout to use between Mobile and Desktop Platforms variations.
     * @returns {boolean}
     */
    isMobilePlatform() {
        return mobilePlatforms.includes(this.platform.name);
    }
}

/**
 * Replace the given tracking element with the given placeholder.
 * Notes:
 *  1. This function also dispatches events targeting the original and
 *     placeholder elements. That way, the surrogate scripts can use the event
 *     targets to keep track of which placeholder corresponds to which tracking
 *     element.
 *  2. To achieve that, the original and placeholder elements must be in the DOM
 *     at the time the events are dispatched. Otherwise, the events will not
 *     bubble up and the surrogate script will miss them.
 *  3. Placeholder must be shown immediately (to avoid a flicker for the user),
 *     but the events must only be sent once the document (and therefore
 *     surrogate scripts) have loaded.
 *  4. Therefore, we hide the element until the page has loaded, then dispatch
 *     the events after page load, and then remove the element from the DOM.
 *  5. The "ddg-ctp-ready" event needs to be dispatched _after_ the element
 *     replacement events have fired. That is why a setTimeout is required
 *     before dispatching "ddg-ctp-ready".
 *
 *  Also note, this all assumes that the surrogate script that needs these
 *  events will not be loaded asynchronously after the page has finished
 *  loading.
 *
 * @param {DuckWidget} widget
 *   The DuckWidget associated with the tracking element.
 * @param {HTMLElement} trackingElement
 *   The tracking element on the page to replace.
 * @param {HTMLElement} placeholderElement
 *   The placeholder element that should be shown instead.
 */
function replaceTrackingElement(widget, trackingElement, placeholderElement) {
    // In some situations (e.g. YouTube Click to Load previews are
    // enabled/disabled), a second placeholder will be shown for a tracking
    // element.
    const elementToReplace = widget.placeholderElement || trackingElement;

    // Note the placeholder element, so that it can also be replaced later if
    // necessary.
    widget.placeholderElement = placeholderElement;

    // First hide the element, since we need to keep it in the DOM until the
    // events have been dispatched.
    const originalDisplay = [elementToReplace.style.getPropertyValue('display'), elementToReplace.style.getPropertyPriority('display')];
    elementToReplace.style.setProperty('display', 'none', 'important');

    // Add the placeholder element to the page.
    elementToReplace.parentElement.insertBefore(placeholderElement, elementToReplace);

    // While the placeholder is shown (and original element hidden)
    // synchronously, the events are dispatched (and original element removed
    // from the DOM) asynchronously after the page has finished loading.
    // eslint-disable-next-line promise/prefer-await-to-then
    afterPageLoad.then(() => {
        // With page load complete, and both elements in the DOM, the events can
        // be dispatched.
        widget.dispatchEvent(trackingElement, 'ddg-ctp-tracking-element');
        widget.dispatchEvent(placeholderElement, 'ddg-ctp-placeholder-element');

        // Once the events are sent, the tracking element (or previous
        // placeholder) can finally be removed from the DOM.
        elementToReplace.remove();
        elementToReplace.style.setProperty('display', ...originalDisplay);
    });
}

/**
 * Creates a placeholder element for the given tracking element and replaces
 * it on the page.
 * @param {DuckWidget} widget
 *   The CTL 'widget' associated with the tracking element.
 * @param {HTMLIFrameElement} trackingElement
 *   The tracking element on the page that should be replaced with a placeholder.
 */
function createPlaceholderElementAndReplace(widget, trackingElement) {
    if (widget.replaceSettings.type === 'blank') {
        replaceTrackingElement(widget, trackingElement, document.createElement('div'));
    }

    if (widget.replaceSettings.type === 'loginButton') {
        const icon = widget.replaceSettings.icon;
        // Create a button to replace old element
        if (widget.shouldUseCustomElement()) {
            const facebookLoginButton = new DDGCtlLoginButton({
                devMode,
                label: widget.replaceSettings.buttonTextUnblockLogin,
                hoverText: widget.replaceSettings.popupBodyText,
                logoIcon: facebookLogo,
                originalElement: trackingElement,
                learnMore: {
                    // Localized strings for "Learn More" link.
                    readAbout: sharedStrings.readAbout,
                    learnMore: sharedStrings.learnMore,
                },
                onClick: widget.clickFunction.bind(widget),
            }).element;
            facebookLoginButton.classList.add('fb-login-button', 'FacebookLogin__button');
            facebookLoginButton.appendChild(makeFontFaceStyleElement());
            replaceTrackingElement(widget, trackingElement, facebookLoginButton);
        } else {
            const { button, container } = makeLoginButton(
                widget.replaceSettings.buttonText,
                widget.getMode(),
                widget.replaceSettings.popupBodyText,
                icon,
                trackingElement,
            );
            button.addEventListener('click', widget.clickFunction(trackingElement, container));
            replaceTrackingElement(widget, trackingElement, container);
        }
    }

    // Facebook
    if (widget.replaceSettings.type === 'dialog') {
        ctl.addDebugFlag();
        ctl.messaging.notify('updateFacebookCTLBreakageFlags', { ctlFacebookPlaceholderShown: true });
        if (widget.shouldUseCustomElement()) {
            /**
             * Creates a custom HTML element with the placeholder element for blocked
             * embedded content. The constructor gets a list of parameters with the
             * content and event handlers for this HTML element.
             */
            const mobileBlockedPlaceholder = new DDGCtlPlaceholderBlockedElement({
                devMode,
                title: widget.replaceSettings.infoTitle, // Card title text
                body: widget.replaceSettings.infoText, // Card body text
                unblockBtnText: widget.replaceSettings.buttonText, // Unblock button text
                useSlimCard: false, // Flag for using less padding on card (ie YT CTL on mobile)
                originalElement: trackingElement, // The original element this placeholder is replacing.
                learnMore: {
                    // Localized strings for "Learn More" link.
                    readAbout: sharedStrings.readAbout,
                    learnMore: sharedStrings.learnMore,
                },
                onButtonClick: widget.clickFunction.bind(widget),
            });
            mobileBlockedPlaceholder.appendChild(makeFontFaceStyleElement());

            replaceTrackingElement(widget, trackingElement, mobileBlockedPlaceholder);
            showExtraUnblockIfShortPlaceholder(null, mobileBlockedPlaceholder);
        } else {
            const icon = widget.replaceSettings.icon;
            const button = makeButton(widget.replaceSettings.buttonText, widget.getMode());
            const textButton = makeTextButton(widget.replaceSettings.buttonText, widget.getMode());
            const { contentBlock, shadowRoot } = createContentBlock(widget, button, textButton, icon);
            button.addEventListener('click', widget.clickFunction(trackingElement, contentBlock));
            textButton.addEventListener('click', widget.clickFunction(trackingElement, contentBlock));

            replaceTrackingElement(widget, trackingElement, contentBlock);
            showExtraUnblockIfShortPlaceholder(shadowRoot, contentBlock);
        }
    }

    // YouTube
    if (widget.replaceSettings.type === 'youtube-video') {
        ctl.addDebugFlag();
        ctl.messaging.notify('updateYouTubeCTLAddedFlag', { youTubeCTLAddedFlag: true });
        replaceYouTubeCTL(trackingElement, widget);

        // Subscribe to changes to youtubePreviewsEnabled setting
        // and update the CTL state
        ctl.messaging.subscribe('setYoutubePreviewsEnabled', ({ value }) => {
            isYoutubePreviewsEnabled = value;
            replaceYouTubeCTL(trackingElement, widget);
        });
    }
}

/**
 * @param {HTMLIFrameElement} trackingElement
 *   The original tracking element (YouTube video iframe)
 * @param {DuckWidget} widget
 *   The CTL 'widget' associated with the tracking element.
 */
function replaceYouTubeCTL(trackingElement, widget) {
    // Skip replacing tracking element if it has already been unblocked
    if (widget.isUnblocked) {
        return;
    }

    if (isYoutubePreviewsEnabled === true) {
        // Show YouTube Preview for embedded video
        const oldPlaceholder = widget.placeholderElement;
        const { youTubePreview, shadowRoot } = createYouTubePreview(trackingElement, widget);
        resizeElementToMatch(oldPlaceholder || trackingElement, youTubePreview);
        replaceTrackingElement(widget, trackingElement, youTubePreview);
        showExtraUnblockIfShortPlaceholder(shadowRoot, youTubePreview);
    } else {
        // Block YouTube embedded video and display blocking dialog
        widget.autoplay = false;
        const oldPlaceholder = widget.placeholderElement;

        if (widget.shouldUseCustomElement()) {
            /**
             * Creates a custom HTML element with the placeholder element for blocked
             * embedded content. The constructor gets a list of parameters with the
             * content and event handlers for this HTML element.
             */
            const mobileBlockedPlaceholderElement = new DDGCtlPlaceholderBlockedElement({
                devMode,
                title: widget.replaceSettings.infoTitle, // Card title text
                body: widget.replaceSettings.infoText, // Card body text
                unblockBtnText: widget.replaceSettings.buttonText, // Unblock button text
                useSlimCard: true, // Flag for using less padding on card (ie YT CTL on mobile)
                originalElement: trackingElement, // The original element this placeholder is replacing.
                learnMore: {
                    // Localized strings for "Learn More" link.
                    readAbout: sharedStrings.readAbout,
                    learnMore: sharedStrings.learnMore,
                },
                withToggle: {
                    // Toggle config to be displayed in the bottom of the placeholder
                    isActive: false, // Toggle state
                    dataKey: 'yt-preview-toggle', // data-key attribute for button
                    label: widget.replaceSettings.previewToggleText, // Text to be presented with toggle
                    size: widget.isMobilePlatform() ? 'lg' : 'md',
                    onClick: () => ctl.messaging.notify('setYoutubePreviewsEnabled', { youtubePreviewsEnabled: true }), // Toggle click callback
                },
                withFeedback: {
                    label: sharedStrings.shareFeedback,
                    onClick: () => openShareFeedbackPage(),
                },
                onButtonClick: widget.clickFunction.bind(widget),
            });
            mobileBlockedPlaceholderElement.appendChild(makeFontFaceStyleElement());
            mobileBlockedPlaceholderElement.id = trackingElement.id;
            resizeElementToMatch(oldPlaceholder || trackingElement, mobileBlockedPlaceholderElement);
            replaceTrackingElement(widget, trackingElement, mobileBlockedPlaceholderElement);
            showExtraUnblockIfShortPlaceholder(null, mobileBlockedPlaceholderElement);
        } else {
            const { blockingDialog, shadowRoot } = createYouTubeBlockingDialog(trackingElement, widget);
            resizeElementToMatch(oldPlaceholder || trackingElement, blockingDialog);
            replaceTrackingElement(widget, trackingElement, blockingDialog);
            showExtraUnblockIfShortPlaceholder(shadowRoot, blockingDialog);
            hideInfoTextIfNarrowPlaceholder(shadowRoot, blockingDialog, 460);
        }
    }
}

/**
 * Show the extra unblock link in the header if the placeholder or
 * its parent is too short for the normal unblock button to be visible.
 * Note: This does not take into account the placeholder's vertical
 *       position in the parent element.
 * @param {ShadowRoot?} shadowRoot
 * @param {HTMLElement} placeholder Placeholder for tracking element
 */
function showExtraUnblockIfShortPlaceholder(shadowRoot, placeholder) {
    if (!placeholder.parentElement) {
        return;
    }
    const parentStyles = window.getComputedStyle(placeholder.parentElement);
    // Inline elements, like span or p, don't have a height value that we can use because they're
    // not a "block" like element with defined sizes. Because we skip this check on "inline"
    // parents, it might be necessary to traverse up the DOM tree until we find the nearest non
    // "inline" parent to get a reliable height for this check.
    if (parentStyles.display === 'inline') {
        return;
    }
    const { height: placeholderHeight } = placeholder.getBoundingClientRect();
    const { height: parentHeight } = placeholder.parentElement.getBoundingClientRect();

    if ((placeholderHeight > 0 && placeholderHeight <= 200) || (parentHeight > 0 && parentHeight <= 230)) {
        if (shadowRoot) {
            /** @type {HTMLElement?} */
            const titleRowTextButton = shadowRoot.querySelector(`#${titleID + 'TextButton'}`);
            if (titleRowTextButton) {
                titleRowTextButton.style.display = 'block';
            }
        }
        // Avoid the placeholder being taller than the containing element
        // and overflowing.
        /** @type {HTMLElement?} */
        const blockedDiv = shadowRoot?.querySelector('.DuckDuckGoSocialContainer') || placeholder;
        if (blockedDiv) {
            blockedDiv.style.minHeight = 'initial';
            blockedDiv.style.maxHeight = parentHeight + 'px';
            blockedDiv.style.overflow = 'hidden';
        }
    }
}

/**
 * Hide the info text (and move the "Learn More" link) if the placeholder is too
 * narrow.
 * @param {ShadowRoot} shadowRoot
 * @param {HTMLElement} placeholder Placeholder for tracking element
 * @param {number} narrowWidth
 *    Maximum placeholder width (in pixels) for the placeholder to be considered
 *    narrow.
 */
function hideInfoTextIfNarrowPlaceholder(shadowRoot, placeholder, narrowWidth) {
    const { width: placeholderWidth } = placeholder.getBoundingClientRect();
    if (placeholderWidth > 0 && placeholderWidth <= narrowWidth) {
        const buttonContainer = shadowRoot.querySelector('.DuckDuckGoButton.primary')?.parentElement;
        const contentTitle = shadowRoot.getElementById('contentTitle');
        const infoText = shadowRoot.getElementById('infoText');
        /** @type {HTMLElement?} */
        const learnMoreLink = shadowRoot.getElementById('learnMoreLink');

        // These elements will exist, but this check keeps TypeScript happy.
        if (!buttonContainer || !contentTitle || !infoText || !learnMoreLink) {
            return;
        }

        // Remove the information text.
        infoText.remove();
        learnMoreLink.remove();

        // Append the "Learn More" link to the title.
        contentTitle.innerText += '. ';
        learnMoreLink.style.removeProperty('font-size');
        contentTitle.appendChild(learnMoreLink);

        // Improve margin/padding, to ensure as much is displayed as possible.
        buttonContainer.style.removeProperty('margin');
    }
}

/*********************************************************
 *  Messaging to surrogates & extension
 *********************************************************/

/**
 * @typedef unblockClickToLoadContentRequest
 * @property {string} entity
 *   The entity to unblock requests for (e.g. "Facebook, Inc.").
 * @property {boolean} [isLogin=false]
 *   True if we should "allow social login", defaults to false.
 * @property {boolean} [isSurrogateLogin=false]
 *   True if logins triggered by the surrogate (custom login), False if login trigger
 *   by user clicking in our Login button placeholder.
 * @property {string} action
 *   The Click to Load blocklist rule action (e.g. "block-ctl-fb") that should
 *   be allowed. Important since in the future there might be multiple types of
 *   embedded content from the same entity that the user can allow
 *   independently.
 */

/**
 * Send a message to the background to unblock requests for the given entity for
 * the page.
 * @param {unblockClickToLoadContentRequest} message
 * @see {@link ddg-ctp-unblockClickToLoadContent-complete} for the response handler.
 * @returns {Promise<any>}
 */
function unblockClickToLoadContent(message) {
    return ctl.messaging.request('unblockClickToLoadContent', message);
}

/**
 * Handle showing a web modal to request the user for a confirmation or, in some platforms,
 * proceed with the "acceptFunction" call and let the platform handle with each request
 * accordingly.
 * @param {import('../utils').Platform["name"]} platformName
 *   The current platform name where Click to Load is running
 * @param {string} entity
 *   The entity to unblock requests for (e.g. "Facebook, Inc.") if the user
 *   clicks to proceed.
 * @param {function} acceptFunction
 *   The function to call if the user has clicked to proceed.
 * @param {...any} acceptFunctionParams
 *   The parameters passed to acceptFunction when it is called.
 */
function handleUnblockConfirmation(platformName, entity, acceptFunction, ...acceptFunctionParams) {
    // In our mobile platforms, we want to show a native UI to request user unblock
    // confirmation. In these cases we send directly the unblock request to the platform
    // and the platform chooses how to best handle it.
    if (platformsWithNativeModalSupport.includes(platformName)) {
        acceptFunction(...acceptFunctionParams);
        // By default, for other platforms (ie Extension), we show a web modal with a
        // confirmation request to the user before we proceed to unblock the content.
    } else {
        makeModal(entity, acceptFunction, ...acceptFunctionParams);
    }
}

/**
 * Set the ctlFacebookLogin breakage flag for the page, to indicate that the
 * Facebook Click to Load login flow had started if the user should then report
 * the website as broken.
 */
function notifyFacebookLogin() {
    ctl.addDebugFlag();
    ctl.messaging.notify('updateFacebookCTLBreakageFlags', { ctlFacebookLogin: true });
}

/**
 * Unblock the entity, close the login dialog and continue the Facebook login
 * flow. Called after the user clicks to proceed after the warning dialog is
 * shown.
 * @param {string} entity
 */
async function runLogin(entity) {
    if (entity === 'Facebook, Inc.') {
        notifyFacebookLogin();
    }

    const action = entity === 'Youtube' ? 'block-ctl-yt' : 'block-ctl-fb';
    const response = await unblockClickToLoadContent({ entity, action, isLogin: true, isSurrogateLogin: true });
    // If user rejected confirmation modal and content was not unblocked, inform surrogate and stop.
    if (response && response.type === 'ddg-ctp-user-cancel') {
        return abortSurrogateConfirmation(this.entity);
    }
    // Communicate with surrogate to run login
    originalWindowDispatchEvent(
        createCustomEvent('ddg-ctp-run-login', {
            detail: {
                entity,
            },
        }),
    );
}

/**
 * Communicate with the surrogate to abort (ie Abort login when user rejects confirmation dialog)
 * Called after the user cancel from a warning dialog.
 * @param {string} entity
 */
function abortSurrogateConfirmation(entity) {
    originalWindowDispatchEvent(
        createCustomEvent('ddg-ctp-cancel-modal', {
            detail: {
                entity,
            },
        }),
    );
}

function openShareFeedbackPage() {
    ctl.messaging.notify('openShareFeedbackPage');
}

/*********************************************************
 *  Widget building blocks
 *********************************************************/

/**
 * Creates a "Learn more" link element.
 * @param {displayMode} [mode='lightMode']
 * @returns {HTMLAnchorElement}
 */
function getLearnMoreLink(mode = 'lightMode') {
    const linkElement = document.createElement('a');
    linkElement.style.cssText = styles.generalLink + styles[mode].linkFont;
    linkElement.ariaLabel = sharedStrings.readAbout;
    linkElement.href = 'https://help.duckduckgo.com/duckduckgo-help-pages/privacy/embedded-content-protection/';
    linkElement.target = '_blank';
    linkElement.textContent = sharedStrings.learnMore;
    linkElement.id = 'learnMoreLink';
    return linkElement;
}

/**
 * Resizes and positions the target element to match the source element.
 * @param {HTMLElement} sourceElement
 * @param {HTMLElement} targetElement
 */
function resizeElementToMatch(sourceElement, targetElement) {
    const computedStyle = window.getComputedStyle(sourceElement);
    const stylesToCopy = ['position', 'top', 'bottom', 'left', 'right', 'transform', 'margin'];

    // It's apparently preferable to use the source element's size relative to
    // the current viewport, when resizing the target element. However, the
    // declarativeNetRequest API "collapses" (hides) blocked elements. When
    // that happens, getBoundingClientRect will return all zeros.
    // TODO: Remove this entirely, and always use the computed height/width of
    //       the source element instead?
    const { height, width } = sourceElement.getBoundingClientRect();
    if (height > 0 && width > 0) {
        targetElement.style.height = height + 'px';
        targetElement.style.width = width + 'px';
    } else {
        stylesToCopy.push('height', 'width');
    }

    for (const key of stylesToCopy) {
        targetElement.style[key] = computedStyle[key];
    }

    // If the parent element is very small (and its dimensions can be trusted) set a max height/width
    // to avoid the placeholder overflowing.
    if (computedStyle.display !== 'inline') {
        if (targetElement.style.maxHeight < computedStyle.height) {
            targetElement.style.maxHeight = 'initial';
        }
        if (targetElement.style.maxWidth < computedStyle.width) {
            targetElement.style.maxWidth = 'initial';
        }
    }
}

/**
 * Create a `<style/>` element with DDG font-face styles/CSS
 * to be attached to DDG wrapper elements
 * @returns HTMLStyleElement
 */
function makeFontFaceStyleElement() {
    // Put our custom font-faces inside the wrapper element, since
    // @font-face does not work inside a shadowRoot.
    // See https://github.com/mdn/interactive-examples/issues/887.
    const fontFaceStyleElement = document.createElement('style');
    fontFaceStyleElement.textContent = styles.fontStyle;
    return fontFaceStyleElement;
}

/**
 * Create a `<style/>` element with base styles for DDG social container and
 * button to be attached to DDG wrapper elements/shadowRoot, also returns a wrapper
 * class name for Social Container link styles
 * @param {displayMode} [mode='lightMode']
 * @returns {{wrapperClass: string, styleElement: HTMLStyleElement; }}
 */
function makeBaseStyleElement(mode = 'lightMode') {
    // Style element includes our font & overwrites page styles
    const styleElement = document.createElement('style');
    const wrapperClass = 'DuckDuckGoSocialContainer';
    styleElement.textContent = `
        .${wrapperClass} a {
            ${styles[mode].linkFont}
            font-weight: bold;
        }
        .${wrapperClass} a:hover {
            ${styles[mode].linkFont}
            font-weight: bold;
        }
        .DuckDuckGoButton {
            ${styles.button}
        }
        .DuckDuckGoButton > div {
            ${styles.buttonTextContainer}
        }
        .DuckDuckGoButton.primary {
           ${styles[mode].buttonBackground}
        }
        .DuckDuckGoButton.primary > div {
           ${styles[mode].buttonFont}
        }
        .DuckDuckGoButton.primary:hover {
           ${styles[mode].buttonBackgroundHover}
        }
        .DuckDuckGoButton.primary:active {
           ${styles[mode].buttonBackgroundPress}
        }
        .DuckDuckGoButton.secondary {
           ${styles.cancelMode.buttonBackground}
        }
        .DuckDuckGoButton.secondary > div {
            ${styles.cancelMode.buttonFont}
         }
        .DuckDuckGoButton.secondary:hover {
           ${styles.cancelMode.buttonBackgroundHover}
        }
        .DuckDuckGoButton.secondary:active {
           ${styles.cancelMode.buttonBackgroundPress}
        }
    `;
    return { wrapperClass, styleElement };
}

/**
 * Creates an anchor element with no destination. It is expected that a click
 * handler is added to the element later.
 * @param {string} linkText
 * @param {displayMode} mode
 * @returns {HTMLAnchorElement}
 */
function makeTextButton(linkText, mode = 'lightMode') {
    const linkElement = document.createElement('a');
    linkElement.style.cssText = styles.headerLink + styles[mode].linkFont;
    linkElement.textContent = linkText;
    return linkElement;
}

/**
 * Create a button element.
 * @param {string} buttonText
 *   Text to be displayed inside the button.
 * @param {displayMode} [mode='lightMode']
 *   The button is usually styled as the primary call to action, but if
 *   'cancelMode' is specified the button is styled as a secondary call to
 *   action.
 * @returns {HTMLButtonElement} Button element
 */
function makeButton(buttonText, mode = 'lightMode') {
    const button = document.createElement('button');
    button.classList.add('DuckDuckGoButton');
    button.classList.add(mode === 'cancelMode' ? 'secondary' : 'primary');
    if (buttonText) {
        const textContainer = document.createElement('div');
        textContainer.textContent = buttonText;
        button.appendChild(textContainer);
    }
    return button;
}

/**
 * Create a toggle button.
 * @param {displayMode} mode
 * @param {boolean} [isActive=false]
 *   True if the button should be toggled by default.
 * @param {string} [classNames='']
 *   Class names to assign to the button (space delimited).
 * @param {string} [dataKey='']
 *   Value to assign to the button's 'data-key' attribute.
 * @returns {HTMLButtonElement}
 */
function makeToggleButton(mode, isActive = false, classNames = '', dataKey = '') {
    const toggleButton = document.createElement('button');
    toggleButton.className = classNames;
    toggleButton.style.cssText = styles.toggleButton;
    toggleButton.type = 'button';
    toggleButton.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    toggleButton.setAttribute('data-key', dataKey);

    const activeKey = isActive ? 'active' : 'inactive';

    const toggleBg = document.createElement('div');
    toggleBg.style.cssText = styles.toggleButtonBg + styles[mode].toggleButtonBgState[activeKey];

    const toggleKnob = document.createElement('div');
    toggleKnob.style.cssText = styles.toggleButtonKnob + styles.toggleButtonKnobState[activeKey];

    toggleButton.appendChild(toggleBg);
    toggleButton.appendChild(toggleKnob);

    return toggleButton;
}

/**
 * Create a toggle button that's wrapped in a div with some text.
 * @param {string} text
 *   Text to display by the button.
 * @param {displayMode} mode
 * @param {boolean} [isActive=false]
 *   True if the button should be toggled by default.
 * @param {string} [toggleClassNames='']
 *   Class names to assign to the toggle button.
 * @param {string} [textCssStyles='']
 *   Styles to apply to the wrapping div (on top of ones determined by the
 *   display mode.)
 * @param {string} [dataKey='']
 *   Value to assign to the button's 'data-key' attribute.
 * @returns {HTMLDivElement}
 */
function makeToggleButtonWithText(text, mode, isActive = false, toggleClassNames = '', textCssStyles = '', dataKey = '') {
    const wrapper = document.createElement('div');
    wrapper.style.cssText = styles.toggleButtonWrapper;

    const toggleButton = makeToggleButton(mode, isActive, toggleClassNames, dataKey);

    const textDiv = document.createElement('div');
    textDiv.style.cssText = styles.contentText + styles.toggleButtonText + styles[mode].toggleButtonText + textCssStyles;
    textDiv.textContent = text;

    wrapper.appendChild(toggleButton);
    wrapper.appendChild(textDiv);
    return wrapper;
}

/**
 * Create the default block symbol, for when the image isn't available.
 * @returns {HTMLDivElement}
 */
function makeDefaultBlockIcon() {
    const blockedIcon = document.createElement('div');
    const dash = document.createElement('div');
    blockedIcon.appendChild(dash);
    blockedIcon.style.cssText = styles.circle;
    dash.style.cssText = styles.rectangle;
    return blockedIcon;
}

/**
 * Creates a share feedback link element.
 * @returns {HTMLAnchorElement}
 */
function makeShareFeedbackLink() {
    const feedbackLink = document.createElement('a');
    feedbackLink.style.cssText = styles.feedbackLink;
    feedbackLink.target = '_blank';
    feedbackLink.href = '#';
    feedbackLink.text = sharedStrings.shareFeedback;
    // Open Feedback Form page through background event to avoid browser blocking extension link
    feedbackLink.addEventListener('click', function (e) {
        e.preventDefault();
        openShareFeedbackPage();
    });

    return feedbackLink;
}

/**
 * Creates a share feedback link element, wrapped in a styled div.
 * @returns {HTMLDivElement}
 */
function makeShareFeedbackRow() {
    const feedbackRow = document.createElement('div');
    feedbackRow.style.cssText = styles.feedbackRow;

    const feedbackLink = makeShareFeedbackLink();
    feedbackRow.appendChild(feedbackLink);

    return feedbackRow;
}

/**
 * Creates a placeholder Facebook login button. When clicked, a warning dialog
 * is displayed to the user. The login flow only continues if the user clicks to
 * proceed.
 * @param {string} buttonText
 * @param {displayMode} mode
 * @param {string} hoverTextBody
 *   The hover text to display for the button.
 * @param {string?} icon
 *   The source of the icon to display in the button, if null the default block
 *   icon is used instead.
 * @param {HTMLElement} originalElement
 *   The original Facebook login button that this placeholder is replacing.
 *   Note: This function does not actually replace the button, the caller is
 *         expected to do that.
 * @returns {{ container: HTMLDivElement, button: HTMLButtonElement }}
 */
function makeLoginButton(buttonText, mode, hoverTextBody, icon, originalElement) {
    const container = document.createElement('div');
    container.style.cssText = 'position: relative;';
    container.appendChild(makeFontFaceStyleElement());

    const shadowRoot = container.attachShadow({ mode: devMode ? 'open' : 'closed' });
    // inherit any class styles on the button
    container.className = 'fb-login-button FacebookLogin__button';
    const { styleElement } = makeBaseStyleElement(mode);
    styleElement.textContent += `
        #DuckDuckGoPrivacyEssentialsHoverableText {
            display: none;
        }
        #DuckDuckGoPrivacyEssentialsHoverable:hover #DuckDuckGoPrivacyEssentialsHoverableText {
            display: block;
        }
    `;
    shadowRoot.appendChild(styleElement);

    const hoverContainer = document.createElement('div');
    hoverContainer.id = 'DuckDuckGoPrivacyEssentialsHoverable';
    hoverContainer.style.cssText = styles.hoverContainer;
    shadowRoot.appendChild(hoverContainer);

    // Make the button
    const button = makeButton(buttonText, mode);
    // Add blocked icon
    if (!icon) {
        button.appendChild(makeDefaultBlockIcon());
    } else {
        const imgElement = document.createElement('img');
        imgElement.style.cssText = styles.loginIcon;
        imgElement.setAttribute('src', icon);
        imgElement.setAttribute('height', '28px');
        button.appendChild(imgElement);
    }
    hoverContainer.appendChild(button);

    // hover action
    const hoverBox = document.createElement('div');
    hoverBox.id = 'DuckDuckGoPrivacyEssentialsHoverableText';
    hoverBox.style.cssText = styles.textBubble;
    const arrow = document.createElement('div');
    arrow.style.cssText = styles.textArrow;
    hoverBox.appendChild(arrow);
    const branding = createTitleRow('DuckDuckGo');
    branding.style.cssText += styles.hoverTextTitle;
    hoverBox.appendChild(branding);
    const hoverText = document.createElement('div');
    hoverText.style.cssText = styles.hoverTextBody;
    hoverText.textContent = hoverTextBody + ' ';
    hoverText.appendChild(getLearnMoreLink(mode));
    hoverBox.appendChild(hoverText);

    hoverContainer.appendChild(hoverBox);
    const rect = originalElement.getBoundingClientRect();

    // The left side of the hover popup may go offscreen if the
    // login button is all the way on the left side of the page. This
    // If that is the case, dynamically shift the box right so it shows
    // properly.
    if (rect.left < styles.textBubbleLeftShift) {
        const leftShift = -rect.left + 10; // 10px away from edge of the screen
        hoverBox.style.cssText += `left: ${leftShift}px;`;
        const change = (1 - rect.left / styles.textBubbleLeftShift) * (100 - styles.arrowDefaultLocationPercent);
        arrow.style.cssText += `left: ${Math.max(10, styles.arrowDefaultLocationPercent - change)}%;`;
    } else if (rect.left + styles.textBubbleWidth - styles.textBubbleLeftShift > window.innerWidth) {
        const rightShift = rect.left + styles.textBubbleWidth - styles.textBubbleLeftShift;
        const diff = Math.min(rightShift - window.innerWidth, styles.textBubbleLeftShift);
        const rightMargin = 20; // Add some margin to the page, so scrollbar doesn't overlap.
        hoverBox.style.cssText += `left: -${styles.textBubbleLeftShift + diff + rightMargin}px;`;
        const change = (diff / styles.textBubbleLeftShift) * (100 - styles.arrowDefaultLocationPercent);
        arrow.style.cssText += `left: ${Math.max(10, styles.arrowDefaultLocationPercent + change)}%;`;
    } else {
        hoverBox.style.cssText += `left: -${styles.textBubbleLeftShift}px;`;
        arrow.style.cssText += `left: ${styles.arrowDefaultLocationPercent}%;`;
    }

    return {
        button,
        container,
    };
}

/**
 * Creates a privacy warning dialog for the user, so that the user can choose to
 * proceed/abort.
 * @param {string} entity
 *   The entity to unblock requests for (e.g. "Facebook, Inc.") if the user
 *   clicks to proceed.
 * @param {function} acceptFunction
 *   The function to call if the user has clicked to proceed.
 * @param {...any} acceptFunctionParams
 *   The parameters passed to acceptFunction when it is called.
 *   TODO: Have the caller bind these arguments to the function instead.
 */
function makeModal(entity, acceptFunction, ...acceptFunctionParams) {
    const icon = entityData[entity].modalIcon;

    const modalContainer = document.createElement('div');
    modalContainer.setAttribute('data-key', 'modal');
    modalContainer.style.cssText = styles.modalContainer;

    modalContainer.appendChild(makeFontFaceStyleElement());

    const closeModal = () => {
        document.body.removeChild(modalContainer);
        abortSurrogateConfirmation(entity);
    };

    // Protect the contents of our modal inside a shadowRoot, to avoid
    // it being styled by the website's stylesheets.
    const shadowRoot = modalContainer.attachShadow({ mode: devMode ? 'open' : 'closed' });
    const { styleElement } = makeBaseStyleElement('lightMode');
    shadowRoot.appendChild(styleElement);

    const pageOverlay = document.createElement('div');
    pageOverlay.style.cssText = styles.overlay;

    const modal = document.createElement('div');
    modal.style.cssText = styles.modal;

    // Title
    const modalTitle = createTitleRow('DuckDuckGo', null, closeModal);
    modal.appendChild(modalTitle);

    const iconElement = document.createElement('img');
    iconElement.style.cssText = styles.icon + styles.modalIcon;
    iconElement.setAttribute('src', icon);
    iconElement.setAttribute('height', '70px');

    const title = document.createElement('div');
    title.style.cssText = styles.modalContentTitle;
    title.textContent = entityData[entity].modalTitle;

    // Content
    const modalContent = document.createElement('div');
    modalContent.style.cssText = styles.modalContent;

    const message = document.createElement('div');
    message.style.cssText = styles.modalContentText;
    message.textContent = entityData[entity].modalText + ' ';
    message.appendChild(getLearnMoreLink());

    modalContent.appendChild(iconElement);
    modalContent.appendChild(title);
    modalContent.appendChild(message);

    // Buttons
    const buttonRow = document.createElement('div');
    buttonRow.style.cssText = styles.modalButtonRow;
    const allowButton = makeButton(entityData[entity].modalAcceptText, 'lightMode');
    allowButton.style.cssText += styles.modalButton + 'margin-bottom: 8px;';
    allowButton.setAttribute('data-key', 'allow');
    allowButton.addEventListener('click', function doLogin() {
        acceptFunction(...acceptFunctionParams);
        document.body.removeChild(modalContainer);
    });
    const rejectButton = makeButton(entityData[entity].modalRejectText, 'cancelMode');
    rejectButton.setAttribute('data-key', 'reject');
    rejectButton.style.cssText += styles.modalButton;
    rejectButton.addEventListener('click', closeModal);

    buttonRow.appendChild(allowButton);
    buttonRow.appendChild(rejectButton);
    modalContent.appendChild(buttonRow);

    modal.appendChild(modalContent);

    shadowRoot.appendChild(pageOverlay);
    shadowRoot.appendChild(modal);

    document.body.insertBefore(modalContainer, document.body.childNodes[0]);
}

/**
 * Create the "title row" div that contains a placeholder's heading.
 * @param {string} message
 *   The title text to display.
 * @param {HTMLAnchorElement?} [textButton]
 *   The link to display with the title, if any.
 * @param {EventListener} [closeBtnFn]
 *   If provided, a close button is added that calls this function when clicked.
 * @returns {HTMLDivElement}
 */
function createTitleRow(message, textButton, closeBtnFn) {
    // Create row container
    const row = document.createElement('div');
    row.style.cssText = styles.titleBox;

    // Logo
    const logoContainer = document.createElement('div');
    logoContainer.style.cssText = styles.logo;
    const logoElement = document.createElement('img');
    logoElement.setAttribute('src', logoImg);
    logoElement.setAttribute('height', '21px');
    logoElement.style.cssText = styles.logoImg;
    logoContainer.appendChild(logoElement);
    row.appendChild(logoContainer);

    // Content box title
    const msgElement = document.createElement('div');
    msgElement.id = titleID; // Ensure we can find this to potentially hide it later.
    msgElement.textContent = message;
    msgElement.style.cssText = styles.title;
    row.appendChild(msgElement);

    // Close Button
    if (typeof closeBtnFn === 'function') {
        const closeButton = document.createElement('button');
        closeButton.style.cssText = styles.closeButton;
        const closeIconImg = document.createElement('img');
        closeIconImg.setAttribute('src', closeIcon);
        closeIconImg.setAttribute('height', '12px');
        closeIconImg.style.cssText = styles.closeIcon;
        closeButton.appendChild(closeIconImg);
        closeButton.addEventListener('click', closeBtnFn);
        row.appendChild(closeButton);
    }

    // Text button for very small boxes
    if (textButton) {
        textButton.id = titleID + 'TextButton';
        row.appendChild(textButton);
    }

    return row;
}

/**
 * Create a placeholder element (wrapped in a div and shadowRoot), to replace a
 * tracking element with.
 * @param {DuckWidget} widget
 *   Widget corresponding to the tracking element.
 * @param {HTMLButtonElement} button
 *   Primary button that loads the original tracking element (and removed this
 *   placeholder) when clicked.
 * @param {HTMLAnchorElement?} textButton
 *   Link to display next to the title, if any.
 * @param {string?} img
 *   Source of image to display in the placeholder (if any).
 * @param {HTMLDivElement} [bottomRow]
 *   Bottom row to append to the placeholder, if any.
 * @returns {{ contentBlock: HTMLDivElement, shadowRoot: ShadowRoot }}
 */
function createContentBlock(widget, button, textButton, img, bottomRow) {
    const contentBlock = document.createElement('div');
    contentBlock.style.cssText = styles.wrapperDiv;

    contentBlock.appendChild(makeFontFaceStyleElement());

    // Put everything else inside the shadowRoot of the wrapper element to
    // reduce the chances of the website's stylesheets messing up the
    // placeholder's appearance.
    const shadowRootMode = devMode ? 'open' : 'closed';
    const shadowRoot = contentBlock.attachShadow({ mode: shadowRootMode });

    // Style element includes our font & overwrites page styles
    const { wrapperClass, styleElement } = makeBaseStyleElement(widget.getMode());
    shadowRoot.appendChild(styleElement);

    // Create overall grid structure
    const element = document.createElement('div');
    element.style.cssText = styles.block + styles[widget.getMode()].background + styles[widget.getMode()].textFont;
    if (widget.replaceSettings.type === 'youtube-video') {
        element.style.cssText += styles.youTubeDialogBlock;
    }
    element.className = wrapperClass;
    shadowRoot.appendChild(element);

    // grid of three rows
    const titleRow = document.createElement('div');
    titleRow.style.cssText = styles.headerRow;
    element.appendChild(titleRow);
    titleRow.appendChild(createTitleRow('DuckDuckGo', textButton));

    const contentRow = document.createElement('div');
    contentRow.style.cssText = styles.content;

    if (img) {
        const imageRow = document.createElement('div');
        imageRow.style.cssText = styles.imgRow;
        const imgElement = document.createElement('img');
        imgElement.style.cssText = styles.icon;
        imgElement.setAttribute('src', img);
        imgElement.setAttribute('height', '70px');
        imageRow.appendChild(imgElement);
        element.appendChild(imageRow);
    }

    const contentTitle = document.createElement('div');
    contentTitle.style.cssText = styles.contentTitle;
    contentTitle.textContent = widget.replaceSettings.infoTitle;
    contentTitle.id = 'contentTitle';
    contentRow.appendChild(contentTitle);
    const contentText = document.createElement('div');
    contentText.style.cssText = styles.contentText;
    const contentTextSpan = document.createElement('span');
    contentTextSpan.id = 'infoText';
    contentTextSpan.textContent = widget.replaceSettings.infoText + ' ';
    contentText.appendChild(contentTextSpan);
    contentText.appendChild(getLearnMoreLink());
    contentRow.appendChild(contentText);
    element.appendChild(contentRow);

    const buttonRow = document.createElement('div');
    buttonRow.style.cssText = styles.buttonRow;
    buttonRow.appendChild(button);
    contentText.appendChild(buttonRow);

    if (bottomRow) {
        contentRow.appendChild(bottomRow);
    }

    /** Share Feedback Link */
    if (widget.replaceSettings.type === 'youtube-video') {
        const feedbackRow = makeShareFeedbackRow();
        shadowRoot.appendChild(feedbackRow);
    }

    return { contentBlock, shadowRoot };
}

/**
 * Create the content block to replace embedded YouTube videos/iframes with.
 * @param {HTMLIFrameElement} trackingElement
 * @param {DuckWidget} widget
 * @returns {{ blockingDialog: HTMLElement, shadowRoot: ShadowRoot }}
 */
function createYouTubeBlockingDialog(trackingElement, widget) {
    const button = makeButton(widget.replaceSettings.buttonText, widget.getMode());
    const textButton = makeTextButton(widget.replaceSettings.buttonText, widget.getMode());

    const bottomRow = document.createElement('div');
    bottomRow.style.cssText = styles.youTubeDialogBottomRow;
    const previewToggle = makeToggleButtonWithText(
        widget.replaceSettings.previewToggleText,
        widget.getMode(),
        false,
        '',
        '',
        'yt-preview-toggle',
    );
    previewToggle.addEventListener('click', () =>
        makeModal(widget.entity, () => ctl.messaging.notify('setYoutubePreviewsEnabled', { youtubePreviewsEnabled: true }), widget.entity),
    );
    bottomRow.appendChild(previewToggle);

    const { contentBlock, shadowRoot } = createContentBlock(widget, button, textButton, null, bottomRow);
    contentBlock.id = trackingElement.id;
    contentBlock.style.cssText += styles.wrapperDiv + styles.youTubeWrapperDiv;

    button.addEventListener('click', widget.clickFunction(trackingElement, contentBlock));
    textButton.addEventListener('click', widget.clickFunction(trackingElement, contentBlock));

    return {
        blockingDialog: contentBlock,
        shadowRoot,
    };
}

/**
 * Creates the placeholder element to replace a YouTube video iframe element
 * with a preview image. Mutates widget Object to set the autoplay property
 * as the preview details load.
 * @param {HTMLIFrameElement} originalElement
 *   The YouTube video iframe element.
 * @param {DuckWidget} widget
 *   The widget Object. We mutate this to set the autoplay property.
 * @returns {{ youTubePreview: HTMLElement, shadowRoot: ShadowRoot }}
 *   Object containing the YouTube Preview element and its shadowRoot.
 */
function createYouTubePreview(originalElement, widget) {
    const youTubePreview = document.createElement('div');
    youTubePreview.id = originalElement.id;
    youTubePreview.style.cssText = styles.wrapperDiv + styles.placeholderWrapperDiv;

    youTubePreview.appendChild(makeFontFaceStyleElement());

    // Protect the contents of our placeholder inside a shadowRoot, to avoid
    // it being styled by the website's stylesheets.
    const shadowRoot = youTubePreview.attachShadow({ mode: devMode ? 'open' : 'closed' });
    const { wrapperClass, styleElement } = makeBaseStyleElement(widget.getMode());
    shadowRoot.appendChild(styleElement);

    const youTubePreviewDiv = document.createElement('div');
    youTubePreviewDiv.style.cssText = styles.youTubeDialogDiv;
    youTubePreviewDiv.classList.add(wrapperClass);
    shadowRoot.appendChild(youTubePreviewDiv);

    /** Preview Image */
    const previewImageWrapper = document.createElement('div');
    previewImageWrapper.style.cssText = styles.youTubePreviewWrapperImg;
    youTubePreviewDiv.appendChild(previewImageWrapper);
    // We use an image element for the preview image so that we can ensure
    // the referrer isn't passed.
    const previewImageElement = document.createElement('img');
    previewImageElement.setAttribute('referrerPolicy', 'no-referrer');
    previewImageElement.style.cssText = styles.youTubePreviewImg;
    previewImageWrapper.appendChild(previewImageElement);

    const innerDiv = document.createElement('div');
    innerDiv.style.cssText = styles.youTubePlaceholder;

    /** Top section */
    const topSection = document.createElement('div');
    topSection.style.cssText = styles.youTubeTopSection;
    innerDiv.appendChild(topSection);

    /** Video Title */
    const titleElement = document.createElement('p');
    titleElement.style.cssText = styles.youTubeTitle;
    topSection.appendChild(titleElement);

    /** Text Button on top section */
    // Use darkMode styles because the preview background is dark and causes poor contrast
    // with lightMode button, making it hard to read.
    const textButton = makeTextButton(widget.replaceSettings.buttonText, 'darkMode');
    textButton.id = titleID + 'TextButton';

    textButton.addEventListener('click', widget.clickFunction(originalElement, youTubePreview));
    topSection.appendChild(textButton);

    /** Play Button */
    const playButtonRow = document.createElement('div');
    playButtonRow.style.cssText = styles.youTubePlayButtonRow;

    const playButton = makeButton('', widget.getMode());
    playButton.style.cssText += styles.youTubePlayButton;

    const videoPlayImg = document.createElement('img');
    const videoPlayIcon = widget.replaceSettings.placeholder.videoPlayIcon[widget.getMode()];
    videoPlayImg.setAttribute('src', videoPlayIcon);
    playButton.appendChild(videoPlayImg);

    playButton.addEventListener('click', widget.clickFunction(originalElement, youTubePreview));
    playButtonRow.appendChild(playButton);
    innerDiv.appendChild(playButtonRow);

    /** Preview Toggle */
    const previewToggleRow = document.createElement('div');
    previewToggleRow.style.cssText = styles.youTubePreviewToggleRow;

    // TODO: Use `widget.replaceSettings.placeholder.previewToggleEnabledDuckDuckGoText` for toggle
    // copy when implementing mobile YT CTL Preview
    const previewToggle = makeToggleButtonWithText(
        widget.replaceSettings.placeholder.previewToggleEnabledText,
        widget.getMode(),
        true,
        '',
        styles.youTubePreviewToggleText,
        'yt-preview-toggle',
    );
    previewToggle.addEventListener('click', () => ctl.messaging.notify('setYoutubePreviewsEnabled', { youtubePreviewsEnabled: false }));

    /** Preview Info Text */
    const previewText = document.createElement('div');
    previewText.style.cssText = styles.contentText + styles.toggleButtonText + styles.youTubePreviewInfoText;
    // Since this string contains an anchor element, setting innerText won't
    // work.
    // Warning: This is not ideal! The translated (and original) strings must be
    //          checked very carefully! Any HTML they contain will be inserted.
    //          Ideally, the translation system would allow only certain element
    //          types to be included, and would avoid the URLs for links being
    //          included in the translations.
    previewText.insertAdjacentHTML('beforeend', widget.replaceSettings.placeholder.previewInfoText);
    const previewTextLink = previewText.querySelector('a');
    if (previewTextLink) {
        const newPreviewTextLink = getLearnMoreLink(widget.getMode());
        newPreviewTextLink.innerText = previewTextLink.innerText;
        previewTextLink.replaceWith(newPreviewTextLink);
    }

    previewToggleRow.appendChild(previewToggle);
    previewToggleRow.appendChild(previewText);
    innerDiv.appendChild(previewToggleRow);

    youTubePreviewDiv.appendChild(innerDiv);

    // We use .then() instead of await here to show the placeholder right away
    // while the YouTube endpoint takes it time to respond.
    const videoURL = originalElement.src || originalElement.getAttribute('data-src');
    ctl.messaging
        .request('getYouTubeVideoDetails', { videoURL })
        // eslint-disable-next-line promise/prefer-await-to-then
        .then(({ videoURL: videoURLResp, status, title, previewImage }) => {
            if (!status || videoURLResp !== videoURL) {
                return;
            }
            if (status === 'success') {
                titleElement.innerText = title;
                titleElement.title = title;
                if (previewImage) {
                    previewImageElement.setAttribute('src', previewImage);
                }
                widget.autoplay = true;
            }
        });

    /** Share Feedback Link */
    const feedbackRow = makeShareFeedbackRow();
    shadowRoot.appendChild(feedbackRow);

    return { youTubePreview, shadowRoot };
}

/**
 * @typedef {import('@duckduckgo/messaging').MessagingContext} MessagingContext
 */

export default class ClickToLoad extends ContentFeature {
    /** @type {MessagingContext} */
    #messagingContext;

    async init(args) {
        /**
         * Bail if no messaging backend - this is a debugging feature to ensure we don't
         * accidentally enabled this
         */
        if (!this.messaging) {
            throw new Error('Cannot operate click to load without a messaging backend');
        }
        _messagingModuleScope = this.messaging;
        _addDebugFlag = this.addDebugFlag.bind(this);

        const websiteOwner = args?.site?.parentEntity;
        const settings = args?.featureSettings?.clickToLoad || {};
        const locale = args?.locale || 'en';
        const localizedConfig = getConfig(locale);
        config = localizedConfig.config;
        sharedStrings = localizedConfig.sharedStrings;
        // update styles if asset config was sent
        styles = getStyles(this.assetConfig);

        /**
         * Register Custom Elements only when Click to Load is initialized, to ensure it is only
         * called when config is ready and any previous context have been appropriately invalidated
         * prior when applicable (ie Firefox when hot reloading the Extension)
         */
        registerCustomElements();

        for (const entity of Object.keys(config)) {
            // Strip config entities that are first-party, or aren't enabled in the
            // extension's clickToLoad settings.
            if ((websiteOwner && entity === websiteOwner) || !settings[entity] || settings[entity].state !== 'enabled') {
                delete config[entity];
                continue;
            }

            // Populate the entities and entityData data structures.
            // TODO: Remove them and this logic, they seem unnecessary.

            entities.push(entity);

            const shouldShowLoginModal = !!config[entity].informationalModal;
            const currentEntityData = { shouldShowLoginModal };

            if (shouldShowLoginModal) {
                const { informationalModal } = config[entity];
                currentEntityData.modalIcon = informationalModal.icon;
                currentEntityData.modalTitle = informationalModal.messageTitle;
                currentEntityData.modalText = informationalModal.messageBody;
                currentEntityData.modalAcceptText = informationalModal.confirmButtonText;
                currentEntityData.modalRejectText = informationalModal.rejectButtonText;
            }

            entityData[entity] = currentEntityData;
        }

        // Listen for window events from "surrogate" scripts.
        window.addEventListener('ddg-ctp', (/** @type {CustomEvent} */ event) => {
            if (!('detail' in event)) return;

            const entity = event.detail?.entity;
            if (!entities.includes(entity)) {
                // Unknown entity, reject
                return;
            }
            if (event.detail?.appID) {
                appID = JSON.stringify(event.detail.appID).replace(/"/g, '');
            }
            // Handle login call
            if (event.detail?.action === 'login') {
                // Even if the user cancels the login attempt, consider Facebook Click to
                // Load to have been active on the page if the user reports the page as broken.
                if (entity === 'Facebook, Inc.') {
                    notifyFacebookLogin();
                }

                if (entityData[entity].shouldShowLoginModal) {
                    handleUnblockConfirmation(this.platform.name, entity, runLogin, entity);
                } else {
                    runLogin(entity);
                }
            }
        });
        // Listen to message from Platform letting CTL know that we're ready to
        // replace elements in the page

        this.messaging.subscribe(
            'displayClickToLoadPlaceholders',
            // TODO: Pass `message.options.ruleAction` through, that way only
            //       content corresponding to the entity for that ruleAction need to
            //       be replaced with a placeholder.
            () => this.replaceClickToLoadElements(),
        );

        // Request the current state of Click to Load from the platform.
        // Note: When the response is received, the response handler resolves
        //       the readyToDisplayPlaceholders Promise.
        const clickToLoadState = await this.messaging.request('getClickToLoadState');
        this.onClickToLoadState(clickToLoadState);

        // Then wait for the page to finish loading, and resolve the
        // afterPageLoad Promise.
        if (document.readyState === 'complete') {
            afterPageLoadResolver();
        } else {
            window.addEventListener('load', afterPageLoadResolver, { once: true });
        }
        await afterPageLoad;

        // On some websites, the "ddg-ctp-ready" event is occasionally
        // dispatched too early, before the listener is ready to receive it.
        // To counter that, catch "ddg-ctp-surrogate-load" events dispatched
        // _after_ page, so the "ddg-ctp-ready" event can be dispatched again.
        window.addEventListener('ddg-ctp-surrogate-load', () => {
            originalWindowDispatchEvent(createCustomEvent('ddg-ctp-ready'));
        });

        // Then wait for any in-progress element replacements, before letting
        // the surrogate scripts know to start.
        window.setTimeout(() => {
            originalWindowDispatchEvent(createCustomEvent('ddg-ctp-ready'));
        }, 0);
    }

    /**
     * This is only called by the current integration between Android and Extension and is now
     * used to connect only these Platforms responses with the temporary implementation of
     * SendMessageMessagingTransport that wraps this communication.
     * This can be removed once they have their own Messaging integration.
     */
    update(message) {
        // TODO: Once all Click to Load messages include the feature property, drop
        //       messages that don't include the feature property too.
        if (message?.feature && message?.feature !== 'clickToLoad') return;

        const messageType = message?.messageType;
        if (!messageType) return;

        if (!this._clickToLoadMessagingTransport) {
            throw new Error('_clickToLoadMessagingTransport not ready. Cannot operate click to load without a messaging backend');
        }

        // Send to Messaging layer the response or subscription message received
        // from the Platform.
        return this._clickToLoadMessagingTransport.onResponse(message);
    }

    /**
     * Update Click to Load internal state
     * @param {Object} state Click to Load state response from the Platform
     * @param {boolean} state.devMode Developer or Production environment
     * @param {boolean} state.youtubePreviewsEnabled YouTube Click to Load - YT Previews enabled flag
     */
    onClickToLoadState(state) {
        devMode = state.devMode;
        isYoutubePreviewsEnabled = state.youtubePreviewsEnabled;

        // Mark the feature as ready, to allow placeholder
        // replacements to start.
        readyToDisplayPlaceholdersResolver();
    }

    /**
     * Replace the blocked CTL elements on the page with placeholders.
     * @param {HTMLElement} [targetElement]
     *   If specified, only this element will be replaced (assuming it matches
     *   one of the expected CSS selectors). If omitted, all matching elements
     *   in the document will be replaced instead.
     */
    async replaceClickToLoadElements(targetElement) {
        await readyToDisplayPlaceholders;

        for (const entity of Object.keys(config)) {
            for (const widgetData of Object.values(config[entity].elementData)) {
                const selector = widgetData.selectors.join();

                let trackingElements = [];
                if (targetElement) {
                    if (targetElement.matches(selector)) {
                        trackingElements.push(targetElement);
                    }
                } else {
                    trackingElements = Array.from(document.querySelectorAll(selector));
                }

                await Promise.all(
                    trackingElements.map((trackingElement) => {
                        if (knownTrackingElements.has(trackingElement)) {
                            return Promise.resolve();
                        }

                        knownTrackingElements.add(trackingElement);

                        const widget = new DuckWidget(widgetData, trackingElement, entity, this.platform);
                        return createPlaceholderElementAndReplace(widget, trackingElement);
                    }),
                );
            }
        }
    }

    /**
     * @returns {MessagingContext}
     */
    get messagingContext() {
        if (this.#messagingContext) return this.#messagingContext;
        this.#messagingContext = this._createMessagingContext();
        return this.#messagingContext;
    }

    // Messaging layer between Click to Load and the Platform
    get messaging() {
        if (this._messaging) return this._messaging;

        if (this.platform.name === 'extension') {
            this._clickToLoadMessagingTransport = new SendMessageMessagingTransport();
            const config = new TestTransportConfig(this._clickToLoadMessagingTransport);
            this._messaging = new Messaging(this.messagingContext, config);
            return this._messaging;
        } else if (this.platform.name === 'ios' || this.platform.name === 'macos') {
            const config = new WebkitMessagingConfig({
                secret: '',
                hasModernWebkitAPI: true,
                webkitMessageHandlerNames: ['contentScopeScriptsIsolated'],
            });
            this._messaging = new Messaging(this.messagingContext, config);
            return this._messaging;
        } else {
            // TODO: Android does support Messaging now, but CTL is not yet integrated there.
            throw new Error('Messaging not supported yet on platform: ' + this.name);
        }
    }
}
