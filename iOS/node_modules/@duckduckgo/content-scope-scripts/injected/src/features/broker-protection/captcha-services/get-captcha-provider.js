import { PirError } from '../types';
import { captchaFactory } from './providers/registry';

/**
 * Gets the captcha provider for the getCaptchaInfo action
 * @param {Document | HTMLElement} root
 * @param {HTMLElement} captchaContainer
 * @param {string} captchaType
 */
export function getCaptchaProvider(root, captchaContainer, captchaType) {
    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
        return PirError.create(`[getCaptchaProvider] could not find captcha provider with type ${captchaType}`);
    }

    if (captchaProvider.isSupportedForElement(root, captchaContainer)) {
        return captchaProvider;
    }

    const detectedProvider = captchaFactory.detectProvider(root, captchaContainer);
    if (!detectedProvider) {
        return PirError.create(
            `[getCaptchaProvider] could not detect captcha provider for ${captchaType} captcha and element ${captchaContainer}`,
        );
    }

    // TODO fire a pixel
    // if the captcha provider type is different from the expected type, log a warning
    console.warn(
        `[getCaptchaProvider] mismatch between expected capctha type ${captchaType} and detected type ${detectedProvider.getType()}`,
    );

    return detectedProvider;
}

/**
 * Gets the captcha provider for the solveCaptcha action
 * @param {HTMLElement} captchaContainer
 * @param {string} captchaType
 */
export function getCaptchaSolveProvider(captchaContainer, captchaType) {
    const captchaProvider = captchaFactory.getProviderByType(captchaType);
    if (!captchaProvider) {
        return PirError.create(`[getCaptchaSolveProvider] could not find captcha provider with type ${captchaType}`);
    }

    if (captchaProvider.canSolve(captchaContainer)) {
        return captchaProvider;
    }

    const detectedProvider = captchaFactory.detectSolveProvider(captchaContainer);
    if (!detectedProvider) {
        return PirError.create(
            `[getCaptchaSolveProvider] could not detect captcha provider for ${captchaType} captcha and element ${captchaContainer}`,
        );
    }

    // TODO fire a pixel
    // if the captcha provider type is different from the expected type, log a warning
    console.warn(
        `[getCaptchaSolveProvider] mismatch between expected captha type ${captchaType} and detected type ${detectedProvider.getType()}`,
    );

    return detectedProvider;
}
