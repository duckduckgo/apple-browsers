/**
 *
 * ## Decision flow for `mouseover` (appending Dax)
 *
 * We'll try to append Dax icons onto thumbnails, if the following conditions are met:
 *
 * 1. User has Duck Player configured to 'always ask' (the default)
 * 2. `thumbnailOverlays` is enabled in the remote config
 *
 * If those are met, the following steps occur:
 *
 * - let `stack` be the entire element stack below the cursor
 * - let `eventTarget` be the event target that received the mouseover event `(e.target)`
 * - **exit** if any element in `stack` matches a css selector in `[config] hoverExcluded`
 * - let `match` be the first element that satisfies both conditions:
 *   1. matches the `[config] thumbLink` CSS selector
 *   2. can be converted into a valid DuckPlayer URL
 * - **exit** if `match` was not found, or a valid link could not be created
 * - **exit** if `match` is contained within any parent element defined in `[config] excludedRegions`
 * - **exit** if `match` contains any sub-links (nested `<a>` tags)
 * - **exit** if `match` does NOT contain an `img` tag
 * - if we get this far, mark `match` as a valid link element, then:
 *   - append Dax overlay to `match` ONLY if:
 *     - `eventTarget` is equal to `match`, or
 *     - `eventTarget` *contains* `match`, or
 *     - `eventTarget` matches a CSS selector in `[config] allowedEventTargets`
 *
 * ## Decision flow for `click interceptions` (opening Duck Player)
 *
 * We'll try to intercept clicks on thumbnails, if the following conditions are met:
 *
 * 1. User has Duck Player configured to 'enabled'
 * 2. `clickInterception` is enabled in the remote config
 *
 * If those are met, the following steps occur:
 *
 * - let `stack` be the entire element stack below the cursor when clicked
 * - let `eventTarget` be the event target that received click event `(e.target)`
 * - **exit** if any element in `stack` matches a css selector in `[config] clickExcluded`
 * - let `match` be the first element that satisfies both conditions:
 *     1. matches the `[config] thumbLink` CSS selector
 *     2. can be converted into a valid DuckPlayer URL
 * - **exit** if `match` was not found, or a valid link could not be created
 * - **exit** if `match` is contained within any parent element defined in `[config] excludedRegions`
 * - if we get this far, mark `match` as a valid link element, then:
 *     - prevent default + propagation on the event ONLY if:
 *         - `eventTarget` is equal to `match`, or
 *         - `eventTarget` *contains* `match`, or
 *         - `eventTarget` matches a CSS selector in `[config] allowedEventTargets`
 *     - otherwise, do nothing
 *
 * @module Duck Player Thumbnails
 */

import { SideEffects, VideoParams } from './util.js';
import { IconOverlay } from './icon-overlay.js';
import { Environment } from './environment.js';
import { OpenInDuckPlayerMsg, Pixel } from './overlay-messages.js';

/**
 * @typedef ThumbnailParams
 * @property {import("../duck-player.js").OverlaysFeatureSettings} settings
 * @property {import("./environment.js").Environment} environment
 * @property {import("../duck-player.js").DuckPlayerOverlayMessages} messages
 */

/**
 * This features covers the implementation
 */
export class Thumbnails {
    sideEffects = new SideEffects();
    /**
     * @param {ThumbnailParams} params
     */
    constructor(params) {
        this.settings = params.settings;
        this.messages = params.messages;
        this.environment = params.environment;
    }

    /**
     * Perform side effects
     */
    init() {
        this.sideEffects.add('showing overlays on hover', () => {
            const { selectors } = this.settings;
            const parentNode = document.documentElement || document.body;

            // create the icon & append it to the page
            const icon = new IconOverlay();
            icon.appendHoverOverlay((href) => {
                if (this.environment.opensVideoOverlayLinksViaMessage) {
                    this.messages.sendPixel(new Pixel({ name: 'play.use.thumbnail' }));
                }

                this.messages.openDuckPlayer(new OpenInDuckPlayerMsg({ href }));
            });

            // remember when a none-dax click occurs - so that we can avoid re-adding the
            // icon whilst the page is navigating
            let clicked = false;

            // detect all click, if it's anywhere on the page
            // but in the icon overlay itself, then just hide the overlay
            const clickHandler = (e) => {
                const overlay = icon.getHoverOverlay();
                if (overlay?.contains(e.target)) {
                    // do nothing here, the click will have been handled by the overlay
                } else if (overlay) {
                    clicked = true;
                    icon.hideOverlay(overlay);
                    icon.hoverOverlayVisible = false;
                    setTimeout(() => {
                        clicked = false;
                    }, 0);
                }
            };

            parentNode.addEventListener('click', clickHandler, true);

            const removeOverlay = () => {
                const overlay = icon.getHoverOverlay();
                if (overlay) {
                    icon.hideOverlay(overlay);
                    icon.hoverOverlayVisible = false;
                }
            };

            const appendOverlay = (element) => {
                if (element && element.isConnected) {
                    icon.moveHoverOverlayToVideoElement(element);
                }
            };

            // detect hovers and decide to show hover icon, or not
            const mouseOverHandler = (e) => {
                if (clicked) return;
                const hoverElement = findElementFromEvent(selectors.thumbLink, selectors.hoverExcluded, e);
                const validLink = isValidLink(hoverElement, selectors.excludedRegions);

                // if it's not an element we care about, bail early and remove the overlay
                if (!hoverElement || !validLink) {
                    return removeOverlay();
                }

                // ensure it doesn't contain sub-links
                if (hoverElement.querySelector('a[href]')) {
                    return removeOverlay();
                }

                // only add Dax when this link also contained an img
                if (!hoverElement.querySelector('img')) {
                    return removeOverlay();
                }

                // if the hover target is the match, or contains the match, all good
                if (e.target === hoverElement || hoverElement?.contains(e.target)) {
                    return appendOverlay(hoverElement);
                }

                // finally, check the 'allowedEventTargets' to see if the hover occurred in an element
                // that we know to be a thumbnail overlay, like a preview
                const matched = selectors.allowedEventTargets.find((css) => e.target.matches(css));
                if (matched) {
                    appendOverlay(hoverElement);
                }
            };

            parentNode.addEventListener('mouseover', mouseOverHandler, true);

            return () => {
                parentNode.removeEventListener('mouseover', mouseOverHandler, true);
                parentNode.removeEventListener('click', clickHandler, true);
                icon.destroy();
            };
        });
    }

    destroy() {
        this.sideEffects.destroy();
    }
}

export class ClickInterception {
    sideEffects = new SideEffects();
    /**
     * @param {ThumbnailParams} params
     */
    constructor(params) {
        this.settings = params.settings;
        this.messages = params.messages;
        this.environment = params.environment;
    }

    /**
     * Perform side effects
     */
    init() {
        this.sideEffects.add('intercepting clicks', () => {
            const { selectors } = this.settings;
            const parentNode = document.documentElement || document.body;

            const clickHandler = (e) => {
                const elementInStack = findElementFromEvent(selectors.thumbLink, selectors.clickExcluded, e);
                const validLink = isValidLink(elementInStack, selectors.excludedRegions);

                const block = (href) => {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    this.messages.openDuckPlayer({ href });
                };

                // if there's no match, return early
                if (!validLink) {
                    return;
                }

                // if the hover target is the match, or contains the match, all good
                if (e.target === elementInStack || elementInStack?.contains(e.target)) {
                    return block(validLink);
                }

                // finally, check the 'allowedEventTargets' to see if the hover occurred in an element
                // that we know to be a thumbnail overlay, like a preview
                const matched = selectors.allowedEventTargets.find((css) => e.target.matches(css));
                if (matched) {
                    block(validLink);
                }
            };

            parentNode.addEventListener('click', clickHandler, true);

            return () => {
                parentNode.removeEventListener('click', clickHandler, true);
            };
        });
    }

    destroy() {
        this.sideEffects.destroy();
    }
}

/**
 * @param {string} selector
 * @param {string[]} excludedSelectors
 * @param {MouseEvent} e
 * @return {HTMLElement|null}
 */
function findElementFromEvent(selector, excludedSelectors, e) {
    /** @type {HTMLElement | null} */
    let matched = null;

    const fastPath = excludedSelectors.length === 0;

    for (const element of document.elementsFromPoint(e.clientX, e.clientY)) {
        // bail early if this item was excluded anywhere in the element stack
        if (excludedSelectors.some((ex) => element.matches(ex))) {
            return null;
        }

        // we cannot return this immediately, because another element in the stack
        // might have been excluded
        if (element.matches(selector)) {
            // in lots of cases we can just return the element as soon as it's found, to prevent
            // checking the entire stack
            matched = /** @type {HTMLElement} */ (element);
            if (fastPath) return matched;
        }
    }
    return matched;
}

/**
 * @param {HTMLElement|null} element
 * @param {string[]} excludedRegions
 * @return {string | null | undefined}
 */
function isValidLink(element, excludedRegions) {
    if (!element) return null;

    /**
     * Does this element exist inside an excluded region?
     */
    const existsInExcludedParent = excludedRegions.some((selector) => {
        for (const parent of document.querySelectorAll(selector)) {
            if (parent.contains(element)) return true;
        }
        return false;
    });

    /**
     * Does this element exist inside an excluded region?
     * If so, bail
     */
    if (existsInExcludedParent) return null;

    /**
     * We shouldn't be able to get here, but this keeps Typescript happy
     * and is a good check regardless
     */
    if (!('href' in element)) return null;

    /**
     * If we get here, we're trying to convert the `element.href`
     * into a valid Duck Player URL
     */
    return VideoParams.fromHref(element.href)?.toPrivatePlayerUrl();
}

export { SideEffects, VideoParams, Environment };
