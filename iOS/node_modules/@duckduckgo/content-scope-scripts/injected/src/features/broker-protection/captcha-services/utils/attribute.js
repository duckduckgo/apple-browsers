/**
 * Extracts the value from an elment's attribute.
 *
 * @param {Object} options - The options object
 * @param {HTMLElement } options.element - The element to extract the attribute from
 * @param {string} options.attrName - The name of the attribute to extract
 * @returns {string} The value of the requested attribute
 * @throws {Error} If the element is not found or the attribute is missing
 */
export function getAttributeValue({ element, attrName }) {
    if (!element) {
        throw Error('[getAttributeValue] element parameter is required');
    }

    const attributeValue = element.getAttribute(attrName);
    if (!attributeValue) {
        throw Error(`[getAttributeValue] ${attrName} is not defined or has no value`);
    }

    return attributeValue;
}
