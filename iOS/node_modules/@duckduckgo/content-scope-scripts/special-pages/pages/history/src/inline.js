/**
 * This script is designed to be run before the application loads, use it to set values
 * that might be needed in CSS or JS
 */

const param = new URLSearchParams(window.location.search).get('platform');

if (isAllowed(param)) {
    document.documentElement.dataset.platform = String(param);
} else {
    document.documentElement.dataset.platform = import.meta.injectName;
}

/**
 * @param {any} input
 * @returns {input is ImportMeta['injectName']}
 */
function isAllowed(input) {
    /** @type {ImportMeta['injectName'][]} */
    const allowed = ['windows', 'apple', 'integration'];
    return allowed.includes(input);
}
