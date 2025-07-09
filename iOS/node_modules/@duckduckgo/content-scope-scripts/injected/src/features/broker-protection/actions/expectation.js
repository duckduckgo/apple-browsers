import { ErrorResponse, SuccessResponse } from '../types.js';
import { expectMany } from '../utils/expectations.js';

/**
 * @param {Record<string, any>} action
 * @param {Document} root
 * @return {import('../types.js').ActionResponse}
 */
export function expectation(action, root = document) {
    const results = expectMany(action.expectations, root);

    // filter out good results + silent failures, leaving only fatal errors
    const errors = results
        .filter((x, index) => {
            if (x.result === true) return false;
            if (action.expectations[index].failSilently) return false;
            return true;
        })
        .map((x) => {
            return 'error' in x ? x.error : 'unknown error';
        });

    if (errors.length > 0) {
        return new ErrorResponse({ actionID: action.id, message: errors.join(', ') });
    }

    // only run later actions if every expectation was met
    const runActions = results.every((x) => x.result === true);

    if (action.actions?.length && runActions) {
        return new SuccessResponse({
            actionID: action.id,
            actionType: action.actionType,
            response: null,
            next: action.actions,
        });
    }

    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
}
