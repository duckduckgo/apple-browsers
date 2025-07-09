import { getUrlParameter } from '../../utils/url';

/**
 * Extracts a site key from a captcha element's URL search parameters.
 *
 * @param {Object} options - The options object
 * @param {HTMLElement | null} options.captchaElement - The DOM element containing the captcha
 * @param {string} options.siteKeyAttrName - The name of the search parameter containing the site key
 * @returns {string | null} The site key extracted from the captcha element's URL or null if not found
 * @throws {Error}
 */
export function getSiteKeyFromSearchParam({ captchaElement, siteKeyAttrName }) {
    if (!captchaElement) {
        throw Error('[getSiteKeyFromSearchParam] could not find captcha');
    }

    if (!('src' in captchaElement)) {
        throw Error('[getSiteKeyFromSearchParam] missing src attribute');
    }

    return getUrlParameter(String(captchaElement.src), siteKeyAttrName);
}
