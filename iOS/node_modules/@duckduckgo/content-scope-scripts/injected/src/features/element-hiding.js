import ContentFeature from '../content-feature';
import { isBeingFramed, injectGlobalStyles } from '../utils';

let adLabelStrings = [];
const parser = new DOMParser();
let hiddenElements = new WeakMap();
let modifiedElements = new WeakMap();
let appliedRules = new Set();
let shouldInjectStyleTag = false;
let mediaAndFormSelectors = 'video,canvas,embed,object,audio,map,form,input,textarea,select,option,button';
let hideTimeouts = [0, 100, 300, 500, 1000, 2000, 3000];
let unhideTimeouts = [1250, 2250, 3000];

/** @type {ElementHiding} */
let featureInstance;

/**
 * Hide DOM element if rule conditions met
 * @param {HTMLElement} element
 * @param {Object} rule
 * @param {HTMLElement} [previousElement]
 */
function collapseDomNode(element, rule, previousElement) {
    if (!element) {
        return;
    }
    const type = rule.type;
    const alreadyHidden = hiddenElements.has(element);
    const alreadyModified = modifiedElements.has(element) && modifiedElements.get(element) === rule.type;
    // return if the element has already been hidden, or modified by the same rule type
    if (alreadyHidden || alreadyModified) {
        return;
    }

    switch (type) {
        case 'hide':
            hideNode(element);
            break;
        case 'hide-empty':
            if (isDomNodeEmpty(element)) {
                hideNode(element);
                appliedRules.add(rule);
            }
            break;
        case 'closest-empty':
            // hide the outermost empty node so that we may unhide if ad loads
            if (isDomNodeEmpty(element)) {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                collapseDomNode(element.parentNode, rule, element);
            } else if (previousElement) {
                hideNode(previousElement);
                appliedRules.add(rule);
            }
            break;
        case 'modify-attr':
            modifyAttribute(element, rule.values);
            break;
        case 'modify-style':
            modifyStyle(element, rule.values);
            break;
        default:
            break;
    }
}

/**
 * Unhide previously hidden DOM element if content loaded into it
 * @param {HTMLElement} element
 * @param {Object} rule
 */
function expandNonEmptyDomNode(element, rule) {
    if (!element) {
        return;
    }
    const type = rule.type;

    const alreadyHidden = hiddenElements.has(element);

    switch (type) {
        case 'hide':
            // only care about rule types that specifically apply to empty elements
            break;
        case 'hide-empty':
        case 'closest-empty':
            if (alreadyHidden && !isDomNodeEmpty(element)) {
                unhideNode(element);
            } else if (type === 'closest-empty') {
                // iterate upwards from matching DOM elements until we arrive at previously
                // hidden element. Unhide element if it contains visible content.
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                expandNonEmptyDomNode(element.parentNode, rule);
            }
            break;
        default:
            break;
    }
}

/**
 * Hide DOM element
 * @param {HTMLElement} element
 */
function hideNode(element) {
    // maintain a reference to each hidden element along with the properties
    // that are being overwritten
    const cachedDisplayProperties = {
        display: element.style.display,
        'min-height': element.style.minHeight,
        height: element.style.height,
    };
    hiddenElements.set(element, cachedDisplayProperties);

    // apply styles to hide element
    element.style.setProperty('display', 'none', 'important');
    element.style.setProperty('min-height', '0px', 'important');
    element.style.setProperty('height', '0px', 'important');
    element.hidden = true;
    // add debug flag to site breakage reports
    featureInstance.addDebugFlag();
}

/**
 * Show previously hidden DOM element
 * @param {HTMLElement} element
 */
function unhideNode(element) {
    const cachedDisplayProperties = hiddenElements.get(element);
    if (!cachedDisplayProperties) {
        return;
    }

    for (const prop in cachedDisplayProperties) {
        element.style.setProperty(prop, cachedDisplayProperties[prop]);
    }
    hiddenElements.delete(element);
    element.hidden = false;
}

/**
 * Check if DOM element contains visible content
 * @param {HTMLElement} node
 */
function isDomNodeEmpty(node) {
    // no sense wasting cycles checking if the page's body element is empty
    if (node.tagName === 'BODY') {
        return false;
    }
    // use a DOMParser to remove all metadata elements before checking if
    // the node is empty.
    const parsedNode = parser.parseFromString(node.outerHTML, 'text/html').documentElement;
    parsedNode.querySelectorAll('base,link,meta,script,style,template,title,desc').forEach((el) => {
        el.remove();
    });

    const visibleText = parsedNode.innerText.trim().toLocaleLowerCase().replace(/:$/, '');
    const mediaAndFormContent = parsedNode.querySelector(mediaAndFormSelectors);
    const frameElements = [...parsedNode.querySelectorAll('iframe')];
    // query original node instead of parsedNode for img elements since heuristic relies
    // on size of image elements
    const imageElements = [...node.querySelectorAll('img,svg')];
    // about:blank iframes don't count as content, return true if:
    // - node doesn't contain any iframes
    // - node contains iframes, all of which are hidden or have src='about:blank'
    const noFramesWithContent = frameElements.every((frame) => {
        return frame.hidden || frame.src === 'about:blank';
    });
    // ad containers often contain tracking pixels and other small images (eg adchoices logo).
    // these should be treated as empty and hidden, but real images should not.
    const visibleImages = imageElements.some((image) => {
        return image.getBoundingClientRect().width > 20 || image.getBoundingClientRect().height > 20;
    });

    if (
        (visibleText === '' || adLabelStrings.includes(visibleText)) &&
        mediaAndFormContent === null &&
        noFramesWithContent &&
        !visibleImages
    ) {
        return true;
    }
    return false;
}

/**
 * Modify specified attribute(s) on element
 * @param {HTMLElement} element
 * @param {Object[]} values
 * @param {string} values[].property
 * @param {string} values[].value
 */
function modifyAttribute(element, values) {
    values.forEach((item) => {
        element.setAttribute(item.property, item.value);
    });
    modifiedElements.set(element, 'modify-attr');
}

/**
 * Modify specified style(s) on element
 * @param {HTMLElement} element
 * @param {Object[]} values
 * @param {string} values[].property
 * @param {string} values[].value
 */
function modifyStyle(element, values) {
    values.forEach((item) => {
        element.style.setProperty(item.property, item.value, 'important');
    });
    modifiedElements.set(element, 'modify-style');
}

/**
 * Separate strict hide rules to inject as style tag if enabled
 * @param {Object[]} rules
 * @param {string} rules[].selector
 * @param {string} rules[].type
 */
function extractTimeoutRules(rules) {
    if (!shouldInjectStyleTag) {
        return rules;
    }

    const strictHideRules = [];
    const timeoutRules = [];

    rules.forEach((rule) => {
        if (rule.type === 'hide') {
            strictHideRules.push(rule);
        } else {
            timeoutRules.push(rule);
        }
    });

    injectStyleTag(strictHideRules);
    return timeoutRules;
}

/**
 * Create styletag for strict hide rules and append it to the document
 * @param {Object[]} rules
 * @param {string} rules[].selector
 * @param {string} rules[].type
 */
function injectStyleTag(rules) {
    // wrap selector list in :is(...) to make it a forgiving selector list. this enables
    // us to use selectors not supported in all browsers, eg :has in Firefox
    let selector = '';

    rules.forEach((rule, i) => {
        if (i !== rules.length - 1) {
            selector = selector.concat(rule.selector, ',');
        } else {
            selector = selector.concat(rule.selector);
        }
    });
    const styleTagProperties = 'display:none!important;min-height:0!important;height:0!important;';
    const styleTagContents = `${forgivingSelector(selector)} {${styleTagProperties}}`;

    injectGlobalStyles(styleTagContents);
}

/**
 * Apply list of active element hiding rules to page
 * @param {Object[]} rules
 * @param {string} rules[].selector
 * @param {string} rules[].type
 */
function hideAdNodes(rules) {
    const document = globalThis.document;

    rules.forEach((rule) => {
        const selector = forgivingSelector(rule.selector);
        const matchingElementArray = [...document.querySelectorAll(selector)];
        matchingElementArray.forEach((element) => {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            collapseDomNode(element, rule);
        });
    });
}

/**
 * Iterate over previously hidden elements, unhiding if content has loaded into them
 */
function unhideLoadedAds() {
    const document = globalThis.document;

    appliedRules.forEach((rule) => {
        const selector = forgivingSelector(rule.selector);
        const matchingElementArray = [...document.querySelectorAll(selector)];
        matchingElementArray.forEach((element) => {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            expandNonEmptyDomNode(element, rule);
        });
    });
}

/**
 * Wrap selector(s) in :is(..) to make them forgiving
 */
function forgivingSelector(selector) {
    return `:is(${selector})`;
}

export default class ElementHiding extends ContentFeature {
    init() {
        // eslint-disable-next-line @typescript-eslint/no-this-alias
        featureInstance = this;

        if (isBeingFramed()) {
            return;
        }

        let activeRules;
        const globalRules = this.getFeatureSetting('rules');
        adLabelStrings = this.getFeatureSetting('adLabelStrings');
        shouldInjectStyleTag = this.getFeatureSetting('useStrictHideStyleTag');
        hideTimeouts = this.getFeatureSetting('hideTimeouts') || hideTimeouts;
        unhideTimeouts = this.getFeatureSetting('unhideTimeouts') || unhideTimeouts;
        mediaAndFormSelectors = this.getFeatureSetting('mediaAndFormSelectors') || mediaAndFormSelectors;

        // determine whether strict hide rules should be injected as a style tag
        if (shouldInjectStyleTag) {
            shouldInjectStyleTag = this.matchConditionalFeatureSetting('styleTagExceptions').length === 0;
        }

        // collect all matching rules for domain
        const activeDomainRules = this.matchConditionalFeatureSetting('domains').flatMap((item) => item.rules);

        const overrideRules = activeDomainRules.filter((rule) => {
            return rule.type === 'override';
        });

        const disableDefault = activeDomainRules.some((rule) => {
            return rule.type === 'disable-default';
        });

        // if rule with type 'disable-default' is present, ignore all global rules
        if (disableDefault) {
            activeRules = activeDomainRules.filter((rule) => {
                return rule.type !== 'disable-default';
            });
        } else {
            activeRules = activeDomainRules.concat(globalRules);
        }

        // remove overrides and rules that match overrides from array of rules to be applied to page
        overrideRules.forEach((override) => {
            activeRules = activeRules.filter((rule) => {
                return rule.selector !== override.selector;
            });
        });

        const applyRules = this.applyRules.bind(this);

        // now have the final list of rules to apply, so we apply them when document is loaded
        if (document.readyState === 'loading') {
            window.addEventListener('DOMContentLoaded', () => {
                applyRules(activeRules);
            });
        } else {
            applyRules(activeRules);
        }
        this.activeRules = activeRules;
    }

    urlChanged() {
        if (this.activeRules) {
            this.applyRules(this.activeRules);
        }
    }

    /**
     * Apply relevant hiding rules to page at set intervals
     * @param {Object[]} rules
     * @param {string} rules[].selector
     * @param {string} rules[].type
     */
    applyRules(rules) {
        const timeoutRules = extractTimeoutRules(rules);
        const clearCacheTimer = unhideTimeouts.concat(hideTimeouts).reduce((a, b) => Math.max(a, b), 0) + 100;

        // several passes are made to hide & unhide elements. this is necessary because we're not using
        // a mutation observer but we want to hide/unhide elements as soon as possible, and ads
        // frequently take from several hundred milliseconds to several seconds to load
        hideTimeouts.forEach((timeout) => {
            setTimeout(() => {
                hideAdNodes(timeoutRules);
            }, timeout);
        });

        // check previously hidden ad elements for contents, unhide if content has loaded after hiding.
        // we do this in order to display non-tracking ads that aren't blocked at the request level
        unhideTimeouts.forEach((timeout) => {
            setTimeout(() => {
                // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
                unhideLoadedAds(timeoutRules);
            }, timeout);
        });

        // clear appliedRules and hiddenElements caches once all checks have run
        setTimeout(() => {
            appliedRules = new Set();
            hiddenElements = new WeakMap();
            modifiedElements = new WeakMap();
        }, clearCacheTimer);
    }
}
