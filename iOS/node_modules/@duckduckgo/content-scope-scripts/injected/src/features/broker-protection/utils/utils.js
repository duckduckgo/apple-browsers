/**
 * Get a single element.
 *
 * @param {Node} doc
 * @param {string} selector
 * @return {HTMLElement | null}
 */
export function getElement(doc = document, selector) {
    if (isXpath(selector)) {
        return safeQuerySelectorXPath(doc, selector);
    }

    return safeQuerySelector(doc, selector);
}

/**
 * Get an element by name.
 *
 * @param {Node} doc
 * @param {string} name
 * @return {HTMLElement | null}
 */
export function getElementByTagName(doc = document, name) {
    return safeQuerySelector(doc, `[name="${name}"]`);
}

/**
 * Get an element by src.
 * @param {Node} node
 * @param {string} src
 * @return {HTMLElement | null}
 */
export function getElementWithSrcStart(node = document, src) {
    return safeQuerySelector(node, `[src^="${src}"]`);
}

/**
 * Get an array of elements
 *
 * @param {Node} doc
 * @param {string} selector
 * @return {HTMLElement[] | null}
 */
export function getElements(doc = document, selector) {
    if (isXpath(selector)) {
        return safeQuerySelectorAllXpath(doc, selector);
    }

    return safeQuerySelectorAll(doc, selector);
}

/**
 * Test if a given selector matches an element.
 *
 * @param {HTMLElement} element
 * @param {string} selector
 */
export function getElementMatches(element, selector) {
    try {
        if (isXpath(selector)) {
            return matchesXPath(element, selector) ? element : null;
        } else {
            return element.matches(selector) ? element : null;
        }
    } catch (e) {
        console.error('getElementMatches threw: ', e);
        return null;
    }
}

/**
 * This is a xpath version of `element.matches(CSS_SELECTOR)`
 * @param {HTMLElement} element
 * @param {string} selector
 * @return {boolean}
 */
function matchesXPath(element, selector) {
    const xpathResult = document.evaluate(selector, element, null, XPathResult.BOOLEAN_TYPE, null);

    return xpathResult.booleanValue;
}

/**
 * @param {unknown} selector
 * @returns {boolean}
 */
function isXpath(selector) {
    if (!(typeof selector === 'string')) return false;

    // see: https://www.w3.org/TR/xpath20/
    // "When the context item is a node, it can also be referred to as the context node. The context item is returned by an expression consisting of a single dot"
    if (selector === '.') return true;
    return selector.startsWith('//') || selector.startsWith('./') || selector.startsWith('(');
}

/**
 * @param {Element|Node} element
 * @param selector
 * @returns {HTMLElement[] | null}
 */
function safeQuerySelectorAll(element, selector) {
    try {
        if (element && 'querySelectorAll' in element) {
            return Array.from(element?.querySelectorAll?.(selector));
        }
        return null;
    } catch (e) {
        return null;
    }
}
/**
 * @param {Element|Node} element
 * @param selector
 * @returns {HTMLElement | null}
 */
function safeQuerySelector(element, selector) {
    try {
        if (element && 'querySelector' in element) {
            return element?.querySelector?.(selector);
        }
        return null;
    } catch (e) {
        return null;
    }
}

/**
 * @param {Node} element
 * @param selector
 * @returns {HTMLElement | null}
 */
function safeQuerySelectorXPath(element, selector) {
    try {
        const match = document.evaluate(selector, element, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
        const single = match?.singleNodeValue;
        if (single) {
            return /** @type {HTMLElement} */ (single);
        }
        return null;
    } catch (e) {
        console.log('safeQuerySelectorXPath threw', e);
        return null;
    }
}

/**
 * @param {Element|Node} element
 * @param selector
 * @returns {HTMLElement[] | null}
 */
function safeQuerySelectorAllXpath(element, selector) {
    try {
        // gets all elements matching the xpath query
        const xpathResult = document.evaluate(selector, element, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        if (xpathResult) {
            /** @type {HTMLElement[]} */
            const matchedNodes = [];
            for (let i = 0; i < xpathResult.snapshotLength; i++) {
                const item = xpathResult.snapshotItem(i);
                if (item) matchedNodes.push(/** @type {HTMLElement} */ (item));
            }
            return /** @type {HTMLElement[]} */ (matchedNodes);
        }
        return null;
    } catch (e) {
        console.log('safeQuerySelectorAllXpath threw', e);
        return null;
    }
}

/**
 * @param {number} min
 * @param {number} max
 * @returns {number}
 */
export function generateRandomInt(min, max) {
    return Math.floor(Math.random() * (max - min + 1) + min);
}

/**
 * CleanArray flattens an array of any input, removing nulls, undefined, and empty strings.
 *
 * @template T
 * @param {T | T[] | null | undefined} input - The input to clean.
 * @param {NonNullable<T>[]} prev
 * @return {NonNullable<T>[]} - The cleaned array.
 */
export function cleanArray(input, prev = []) {
    if (!Array.isArray(input)) {
        if (input === null) return prev;
        if (input === undefined) return prev;
        // special case for empty strings
        if (typeof input === 'string') {
            const trimmed = input.trim();
            if (trimmed.length > 0) {
                prev.push(/** @type {NonNullable<T>} */ (trimmed));
            }
        } else {
            prev.push(input);
        }
        return prev;
    }

    for (const item of input) {
        prev.push(...cleanArray(item));
    }

    return prev;
}

/**
 * Determines whether the given input is a non-empty string.
 *
 * @param {any} [input] - The input to be checked.
 * @return {boolean} - True if the input is a non-empty string, false otherwise.
 */
export function nonEmptyString(input) {
    if (typeof input !== 'string') return false;
    return input.trim().length > 0;
}

/**
 * Checks if two strings are a matching pair, ignoring case and leading/trailing white spaces.
 *
 * @param {any} a - The first string to compare.
 * @param {any} b - The second string to compare.
 * @return {boolean} - Returns true if the strings are a matching pair, false otherwise.
 */
export function matchingPair(a, b) {
    if (!nonEmptyString(a)) return false;
    if (!nonEmptyString(b)) return false;
    return a.toLowerCase().trim() === b.toLowerCase().trim();
}

/**
 * Sorts an array of addresses by state, then by city within the state.
 *
 * @param {any} addresses
 * @return {Array}
 */
export function sortAddressesByStateAndCity(addresses) {
    return addresses.sort((a, b) => {
        if (a.state < b.state) {
            return -1;
        }
        if (a.state > b.state) {
            return 1;
        }
        return a.city.localeCompare(b.city);
    });
}

/**
 * Returns a SHA-1 hash of the profile
 */
export async function hashObject(profile) {
    const msgUint8 = new TextEncoder().encode(JSON.stringify(profile)); // encode as (utf-8)
    const hashBuffer = await crypto.subtle.digest('SHA-1', msgUint8); // hash the message
    const hashArray = Array.from(new Uint8Array(hashBuffer)); // convert buffer to byte array
    const hashHex = hashArray.map((b) => b.toString(16).padStart(2, '0')).join(''); // convert bytes to hex string

    return hashHex;
}
