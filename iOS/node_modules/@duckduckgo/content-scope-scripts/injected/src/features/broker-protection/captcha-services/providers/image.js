import { PirError } from '../../types';
import { svgToBase64Jpg, imageToBase64 } from '../utils/image';
import { injectTokenIntoElement } from '../utils/token';
import { isElementType } from '../utils/element';
import { stringifyFunction } from '../utils/stringify-function';

/**
 * @import { CaptchaProvider } from './provider.interface';
 * @implements {CaptchaProvider}
 */
export class ImageProvider {
    getType() {
        return 'image';
    }

    /**
     * @param {Document | HTMLElement} _root
     * @param {HTMLElement} captchaImageElement - The captcha image element
     */
    isSupportedForElement(_root, captchaImageElement) {
        if (!captchaImageElement) {
            return false;
        }

        return isElementType(captchaImageElement, ['img', 'svg']);
    }

    /**
     * @param {HTMLElement} captchaImageElement - The captcha image element
     */
    async getCaptchaIdentifier(captchaImageElement) {
        if (isSVGElement(captchaImageElement)) {
            return await svgToBase64Jpg(captchaImageElement);
        }

        if (isImgElement(captchaImageElement)) {
            return imageToBase64(captchaImageElement);
        }

        return PirError.create(
            `[ImageProvider.getCaptchaIdentifier] could not extract Base64 from image with tag name: ${captchaImageElement.tagName}`,
        );
    }

    getSupportingCodeToInject() {
        return null;
    }

    /**
     * @param {HTMLElement} captchaInputElement - The captcha input element
     */
    canSolve(captchaInputElement) {
        return isElementType(captchaInputElement, ['input', 'textarea']);
    }

    /**
     * @param {HTMLInputElement} captchaInputElement - The captcha input element
     * @param {string} token - The solved captcha token
     */
    injectToken(captchaInputElement, token) {
        return injectTokenIntoElement({ captchaInputElement, token });
    }

    /**
     * @param {HTMLElement} _captchaInputElement - The element containing the captcha
     * @param {string} _token - The solved captcha token
     */
    getSolveCallback(_captchaInputElement, _token) {
        return stringifyFunction({
            functionBody: function callbackNoop() {},
            functionName: 'callbackNoop',
            args: {},
        });
    }
}

/**
 * @param {HTMLElement} element
 * @return {element is SVGElement}
 */
function isSVGElement(element) {
    return isElementType(element, 'svg');
}

/**
 * @param {HTMLElement} element
 * @return {element is HTMLImageElement}
 */
function isImgElement(element) {
    return isElementType(element, 'img');
}
