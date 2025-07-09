/**
 *
 * @param {HTMLElement} element - The element to check
 * @param {string | string[]} tag - The tag name(s) to check against
 * @returns {boolean} - True if the element is of the specified tag name(s), false otherwise
 */
export function isElementType(element, tag) {
    if (Array.isArray(tag)) {
        return tag.some((t) => isElementType(element, t));
    }

    return element.tagName.toLowerCase() === tag.toLowerCase();
}
