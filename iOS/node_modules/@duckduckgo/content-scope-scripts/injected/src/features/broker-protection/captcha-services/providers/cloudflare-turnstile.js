import { getElementByTagName, getElementWithSrcStart } from '../../utils/utils';
import { safeCallWithError } from '../../utils/safe-call';
import { getAttributeValue } from '../utils/attribute';
import { injectTokenIntoElement } from '../utils/token';
import { stringifyFunction } from '../utils/stringify-function';
import { PirError } from '../../types';

/**
 * @typedef {Object} CloudFlareTurnstileProviderConfig
 * @property {string} providerUrl - The captcha provider URL
 * @property {string} responseElementName - The name of the captcha response element
 */

/**
 * @import { CaptchaProvider } from './provider.interface';
 * @implements {CaptchaProvider}
 */
export class CloudFlareTurnstileProvider {
    /**
     * @type {CloudFlareTurnstileProviderConfig}
     */
    #config;

    constructor() {
        this.#config = {
            providerUrl: 'https://challenges.cloudflare.com/turnstile/v0',
            responseElementName: 'cf-turnstile-response',
        };
    }

    getType() {
        return 'cloudFlareTurnstile';
    }

    /**
     * @param {Document | HTMLElement} root
     * @param {HTMLElement} _captchaContainerElement
     * @returns {boolean} Whether the captcha is supported for the element
     */
    isSupportedForElement(root, _captchaContainerElement) {
        // Typically we look within captcha container for isSupportedForElement, but CloudFlare puts the iFrame into the shadow DOM,
        // so we need to look at the script tags on the page instead
        return !!this._getCaptchaScript(root);
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     */
    getCaptchaIdentifier(captchaContainerElement) {
        const sitekeyAttribute = 'data-sitekey';

        return Promise.resolve(
            safeCallWithError(() => getAttributeValue({ element: captchaContainerElement, attrName: sitekeyAttribute }), {
                errorMessage: `[CloudFlareTurnstileProvider.getCaptchaIdentifier] could not extract site key from attribute: ${sitekeyAttribute}`,
            }),
        );
    }

    getSupportingCodeToInject() {
        return null;
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @returns {boolean} Whether the captcha can be solved
     */
    canSolve(captchaContainerElement) {
        const callbackAttribute = 'data-callback';

        const hasCallback = safeCallWithError(() => getAttributeValue({ element: captchaContainerElement, attrName: callbackAttribute }), {
            errorMessage: `[CloudFlareTurnstileProvider.canSolve] could not extract callback function name from attribute: ${callbackAttribute}`,
        });

        if (PirError.isError(hasCallback)) {
            return false;
        }

        const hasResponseElement = safeCallWithError(() => getElementByTagName(captchaContainerElement, this.#config.responseElementName), {
            errorMessage: `[CloudFlareTurnstileProvider.canSolve] could not find response element: ${this.#config.responseElementName}`,
        });

        if (PirError.isError(hasResponseElement)) {
            return false;
        }

        return true;
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token - The solved captcha token
     */
    injectToken(captchaContainerElement, token) {
        return injectTokenIntoElement({ captchaContainerElement, elementName: this.#config.responseElementName, token });
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token - The solved captcha token
     */
    getSolveCallback(captchaContainerElement, token) {
        const callbackAttribute = 'data-callback';

        const callbackFunctionName = safeCallWithError(
            () => getAttributeValue({ element: captchaContainerElement, attrName: callbackAttribute }),
            {
                errorMessage: `[CloudFlareTurnstileProvider.getSolveCallback] could not extract callback function name from attribute: ${callbackAttribute}`,
            },
        );

        if (PirError.isError(callbackFunctionName)) {
            return callbackFunctionName;
        }

        return stringifyFunction({
            /**
             * @param {Object} args - The arguments passed to the function
             * @param {string} args.callbackFunctionName - The callback function name
             * @param {string} args.token - The solved captcha token
             */
            functionBody: function cloudflareCaptchaCallback(args) {
                window[args.callbackFunctionName](args.token);
            },
            functionName: 'cloudflareCaptchaCallback',
            args: { callbackFunctionName, token },
        });
    }

    /**
     * @private
     * @param {Document | HTMLElement} root - The root element to search in
     */
    _getCaptchaScript(root) {
        return getElementWithSrcStart(root, this.#config.providerUrl);
    }
}
