import { safeCall } from './safe-call';

/**
 * Get a URL parameter from a URL string
 * @param {string} url - The URL to parse
 * @param {string} param - The parameter name
 * @returns {string|null} - The parameter value or null
 */
export function getUrlParameter(url, param) {
    if (!url || !param) {
        return null;
    }

    return safeCall(() => new URL(url).searchParams.get(param), { errorMessage: `[getUrlParameter] Error parsing URL: ${url}` });
}

/**
 * Get a URL parameter from a URL hash fragment
 * @param {string} url - The URL to parse
 * @param {string} param - The parameter name
 * @returns {string|null} - The parameter value or null
 */
export function getUrlHashParameter(url, param) {
    if (!url || !param) {
        return null;
    }

    return safeCall(
        () => {
            const hash = new URL(url).hash.slice(1);
            return new URLSearchParams(hash).get(param);
        },
        { errorMessage: '[getUrlHashParameter] error' },
    );
}

/**
 * Remove query parameters from a URL
 * @param {string} url - The URL to clean
 * @returns {string} - URL without query parameters
 */
export function removeUrlQueryParams(url) {
    if (!url) {
        return '';
    }

    return url.split('?')[0];
}
