import { PirError, PirSuccess } from '../../types';
import { safeCallWithError } from '../../utils/safe-call';
import { getElementByTagName } from '../../utils/utils';
import { isElementType } from './element';

/**
 * Inject a token into a named element
 * @import { PirResponse } from '../../types';
 * @param {object} params
 * @param {HTMLElement} [params.captchaContainerElement]  - The element containing the captcha
 * @param {HTMLElement} [params.captchaInputElement]  - The element containing the captcha (optional)
 * @param {string} [params.elementName] - Name attribute of the element to inject into (optional)
 * @param {string} params.token - The token to inject
 * @returns {PirResponse<{ injected: boolean }>} - Whether the token was injected
 */
export function injectTokenIntoElement({ captchaContainerElement, captchaInputElement, elementName, token }) {
    let element;

    if (captchaInputElement) {
        element = captchaInputElement;
    } else if (elementName) {
        element = getElementByTagName(captchaContainerElement, elementName);
    } else {
        return PirError.create(`[injectTokenIntoElement] must pass in either captcha input element or element name`);
    }

    if (!element) {
        return PirError.create(`[injectTokenIntoElement] could not find element to inject token into`);
    }

    return safeCallWithError(
        () => {
            if ((isInputElement(element) && ['text', 'hidden'].includes(element.type)) || isTextAreaElement(element)) {
                element.value = token;
                return PirSuccess.create({ injected: true });
            } else {
                return PirError.create(`[injectTokenIntoElement] element is neither a text input or textarea`);
            }
        },
        { errorMessage: `[injectTokenIntoElement] error injecting token into element` },
    );
}

/**
 * @param {HTMLElement} element
 * @return {element is HTMLInputElement}
 */
function isInputElement(element) {
    return isElementType(element, 'input');
}

/**
 * @param {HTMLElement} element
 * @return {element is HTMLTextAreaElement}
 */
function isTextAreaElement(element) {
    return isElementType(element, 'textarea');
}
