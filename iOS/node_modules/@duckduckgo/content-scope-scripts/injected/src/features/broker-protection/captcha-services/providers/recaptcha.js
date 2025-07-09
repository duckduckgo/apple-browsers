import { getElementByTagName, getElementWithSrcStart } from '../../utils/utils';
import { getSiteKeyFromSearchParam } from '../utils/sitekey';
import { stringifyFunction } from '../utils/stringify-function';
import { injectTokenIntoElement } from '../utils/token';
// TODO move on the same folder level once we deprecate the existing captcha scripts
import { captchaCallback } from '../../actions/captcha-callback';
import { safeCallWithError } from '../../utils/safe-call';

// define the config below to reuse it in the class
/**
 * @typedef {Object} ReCaptchaProviderConfig
 * @property {string} type - The captcha type
 * @property {string} providerUrl - The captcha provider URL
 * @property {string} responseElementName - The name of the captcha response element
 */

/**
 * @import { CaptchaProvider } from './provider.interface';
 * @implements {CaptchaProvider}
 */
export class ReCaptchaProvider {
    /**
     * @type {ReCaptchaProviderConfig}
     */
    #config;

    /**
     * @param {ReCaptchaProviderConfig} config
     */
    constructor(config) {
        this.#config = config;
    }

    getType() {
        return this.#config.type;
    }

    /**
     * @param {Document | HTMLElement} _root
     * @param {HTMLElement} captchaContainerElement
     */
    isSupportedForElement(_root, captchaContainerElement) {
        return !!this._getCaptchaElement(captchaContainerElement);
    }

    /**
     * @param {HTMLElement} captchaContainerElement
     */
    getCaptchaIdentifier(captchaContainerElement) {
        return Promise.resolve(
            safeCallWithError(
                () => getSiteKeyFromSearchParam({ captchaElement: this._getCaptchaElement(captchaContainerElement), siteKeyAttrName: 'k' }),
                { errorMessage: '[ReCaptchaProvider.getCaptchaIdentifier] could not extract site key' },
            ),
        );
    }

    getSupportingCodeToInject() {
        return null;
    }

    /**
     * @param {HTMLElement} _captchaContainerElement - The element containing the captcha
     * @param {string} token
     */
    getSolveCallback(_captchaContainerElement, token) {
        return stringifyFunction({
            functionBody: captchaCallback,
            functionName: 'captchaCallback',
            args: { token },
        });
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     */
    canSolve(captchaContainerElement) {
        return !!getElementByTagName(captchaContainerElement, this.#config.responseElementName);
    }

    /**
     * @param {HTMLElement} captchaContainerElement - The element containing the captcha
     * @param {string} token
     */
    injectToken(captchaContainerElement, token) {
        return injectTokenIntoElement({ captchaContainerElement, elementName: this.#config.responseElementName, token });
    }

    /**
     * @private
     * @param {HTMLElement} captchaContainerElement
     */
    _getCaptchaElement(captchaContainerElement) {
        return getElementWithSrcStart(captchaContainerElement, this.#config.providerUrl);
    }
}
