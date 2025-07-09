import { transformUrl } from './build-url-transforms.js';
import { ErrorResponse, SuccessResponse } from '../types.js';

/**
 * This builds the proper URL given the URL template and userData.
 *
 * @param action
 * @param {Record<string, any>} userData
 * @return {import('../types.js').ActionResponse}
 */
export function buildUrl(action, userData) {
    const result = replaceTemplatedUrl(action, userData);
    if ('error' in result) {
        return new ErrorResponse({ actionID: action.id, message: result.error });
    }

    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: { url: result.url } });
}

/**
 * Perform some basic validations before we continue into the templating.
 *
 * @param action
 * @param userData
 * @return {{url: string} | {error: string}}
 */
export function replaceTemplatedUrl(action, userData) {
    const url = action?.url;
    if (!url) {
        return { error: 'Error: No url provided.' };
    }

    try {
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const _ = new URL(action.url);
    } catch (e) {
        return { error: 'Error: Invalid URL provided.' };
    }

    if (!userData) {
        return { url };
    }

    return transformUrl(action, userData);
}
