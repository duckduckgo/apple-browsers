import { captchaCallback } from './captcha-callback.js';
import { getElement } from '../utils/utils.js';
import { ErrorResponse, SuccessResponse } from '../types.js';

/**
 * Gets the captcha information to send to the backend
 *
 * @param {import('../types.js').PirAction} action
 * @param {Document | HTMLElement} root
 * @return {import('../types.js').ActionResponse}
 */
export function getCaptchaInfo(action, root = document) {
    const pageUrl = window.location.href;
    if (!action.selector) {
        return new ErrorResponse({ actionID: action.id, message: 'missing selector' });
    }

    const captchaDiv = getElement(root, action.selector);

    // if 'captchaDiv' was missing, cannot continue
    if (!captchaDiv) {
        return new ErrorResponse({ actionID: action.id, message: `could not find captchaDiv with selector ${action.selector}` });
    }

    // try 2 different captures
    const captcha =
        getElement(captchaDiv, '[src^="https://www.google.com/recaptcha"]') ||
        getElement(captchaDiv, '[src^="https://newassets.hcaptcha.com/captcha"');

    // ensure we have the elements
    if (!captcha) return new ErrorResponse({ actionID: action.id, message: 'could not find captcha' });
    if (!('src' in captcha)) return new ErrorResponse({ actionID: action.id, message: 'missing src attribute' });

    const captchaUrl = String(captcha.src);
    let captchaType;
    let siteKey;

    if (captchaUrl.includes('recaptcha/api2')) {
        captchaType = 'recaptcha2';
        siteKey = new URL(captchaUrl).searchParams.get('k');
    } else if (captchaUrl.includes('recaptcha/enterprise')) {
        captchaType = 'recaptchaEnterprise';
        siteKey = new URL(captchaUrl).searchParams.get('k');
    } else if (captchaUrl.includes('hcaptcha.com/captcha/v1')) {
        captchaType = 'hcaptcha';
        // hcaptcha sitekey may be in either
        if (captcha instanceof Element) {
            siteKey = captcha.getAttribute('data-sitekey');
        }
        if (!siteKey) {
            try {
                // `new URL(...)` can throw, so it's valid to wrap this in try/catch
                siteKey = new URL(captchaUrl).searchParams.get('sitekey');
            } catch (e) {
                console.warn('error parsing captchaUrl', captchaUrl);
            }
        }
        if (!siteKey) {
            try {
                const hash = new URL(captchaUrl).hash.slice(1);
                siteKey = new URLSearchParams(hash).get('sitekey');
            } catch (e) {
                console.warn('error parsing captchaUrl hash', captchaUrl);
            }
        }
    }

    if (!captchaType) {
        return new ErrorResponse({ actionID: action.id, message: 'Could not extract captchaType.' });
    }
    if (!siteKey) {
        return new ErrorResponse({ actionID: action.id, message: 'Could not extract siteKey.' });
    }

    // Remove query params (which may include PII)
    const pageUrlWithoutParams = pageUrl?.split('?')[0];

    const responseData = {
        siteKey,
        url: pageUrlWithoutParams,
        type: captchaType,
    };

    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: responseData });
}

/**
 * Takes the solved captcha token and injects it into the page to solve the captcha
 *
 * @param action
 * @param {string} token
 * @param {Document} root
 * @return {import('../types.js').ActionResponse}
 */
export function solveCaptcha(action, token, root = document) {
    const selectors = ['h-captcha-response', 'g-recaptcha-response'];
    let solved = false;

    for (const selector of selectors) {
        const match = root.getElementsByName(selector)[0];
        if (match) {
            match.innerHTML = token;
            solved = true;
            break;
        }
    }

    if (solved) {
        const json = JSON.stringify({ token });

        const javascript = `;(function(args) {
            ${captchaCallback.toString()};
            captchaCallback(args);
        })(${json});`;

        return new SuccessResponse({
            actionID: action.id,
            actionType: action.actionType,
            response: { callback: { eval: javascript } },
        });
    }

    return new ErrorResponse({ actionID: action.id, message: 'could not solve captcha' });
}
