import { getElement } from '../utils/utils.js';
import { removeUrlQueryParams } from '../utils/url.js';
import { ErrorResponse, PirError, SuccessResponse } from '../types';
import { getCaptchaProvider, getCaptchaSolveProvider } from './get-captcha-provider';
import { captchaFactory } from './providers/registry.js';
import { getCaptchaInfo as getCaptchaInfoDeprecated, solveCaptcha as solveCaptchaDeprecated } from '../actions/captcha-deprecated';

/**
 *
 * @param {Document | HTMLElement} root
 * @param {import('../types.js').PirAction['selector']} [selector]
 * @returns {HTMLElement | import('../types.js').PirError}
 */
const getCaptchaContainer = (root, selector) => {
    if (!selector) {
        return PirError.create('missing selector');
    }

    const captchaContainer = getElement(root, selector);
    if (!captchaContainer) {
        return PirError.create(`could not find captcha container with selector ${selector}`);
    }

    return captchaContainer;
};

/**
 * Returns the supporting code to inject for the given captcha type
 *
 * @param {import('../types.js').PirAction} action
 * @return {import('../types.js').ActionResponse}
 */
export function getSupportingCodeToInject(action) {
    const { id: actionID, actionType, injectCaptchaHandler: captchaType } = action;
    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: 'getSupportingCodeToInject' });
    if (!captchaType) {
        // ensures backward compatibility with old actions
        return SuccessResponse.create({ actionID, actionType, response: {} });
    }

    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
        return createError(`could not find captchaProvider with type ${captchaType}`);
    }

    return SuccessResponse.create({ actionID, actionType, response: { code: captchaProvider.getSupportingCodeToInject() } });
}

/**
 * Gets the captcha information to send to the backend
 *
 * @param {import('../types.js').PirAction} action
 * @param {Document | HTMLElement} root
 * @return {Promise<import('../types.js').ActionResponse>}
 */
export async function getCaptchaInfo(action, root = document) {
    const { id: actionID, actionType, captchaType, selector } = action;
    if (!captchaType) {
        // ensures backward compatibility with old actions
        return getCaptchaInfoDeprecated(action, root);
    }

    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: `[getCaptchaInfo] captchaType: ${captchaType}` });

    const captchaContainer = getCaptchaContainer(root, selector);
    if (PirError.isError(captchaContainer)) {
        return createError(captchaContainer.error.message);
    }

    const captchaProvider = getCaptchaProvider(root, captchaContainer, captchaType);
    if (PirError.isError(captchaProvider)) {
        return createError(captchaProvider.error.message);
    }

    const captchaIdentifier = await captchaProvider.getCaptchaIdentifier(captchaContainer);
    if (!captchaIdentifier) {
        return createError(`could not extract captcha identifier from the container with selector ${selector}`);
    }

    if (PirError.isError(captchaIdentifier)) {
        return createError(captchaIdentifier.error.message);
    }

    const response = {
        url: removeUrlQueryParams(window.location.href), // query params (which may include PII)
        siteKey: captchaIdentifier,
        type: captchaProvider.getType(),
    };

    return SuccessResponse.create({ actionID, actionType, response });
}

/**
 * Takes the solved captcha token and injects it into the page to solve the captcha
 *
 * @param {import('../types.js').PirAction} action
 * @param {string} token
 * @param {Document} root
 * @return {import('../types.js').ActionResponse}
 */
export function solveCaptcha(action, token, root = document) {
    const { id: actionID, actionType, captchaType, selector } = action;
    if (!captchaType) {
        // ensures backward compatibility with old actions
        return solveCaptchaDeprecated(action, token, root);
    }

    const createError = ErrorResponse.generateErrorResponseFunction({ actionID, context: `[solveCaptcha] captchaType: ${captchaType}` });

    const captchaContainer = getCaptchaContainer(root, selector);
    if (PirError.isError(captchaContainer)) {
        return createError(captchaContainer.error.message);
    }

    const captchaSolveProvider = getCaptchaSolveProvider(captchaContainer, captchaType);
    if (PirError.isError(captchaSolveProvider)) {
        return createError(captchaSolveProvider.error.message);
    }

    if (!captchaSolveProvider.canSolve(captchaContainer)) {
        return createError('cannot solve captcha');
    }

    const tokenResponse = captchaSolveProvider.injectToken(captchaContainer, token);
    if (PirError.isError(tokenResponse)) {
        return createError(tokenResponse.error.message);
    }

    if (!tokenResponse.response.injected) {
        return createError('could not inject token');
    }

    return SuccessResponse.create({
        actionID,
        actionType,
        response: { callback: { eval: captchaSolveProvider.getSolveCallback(captchaContainer, token) } },
    });
}
