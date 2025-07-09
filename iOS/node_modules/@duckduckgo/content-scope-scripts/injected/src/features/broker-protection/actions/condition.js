import { ErrorResponse, SuccessResponse } from '../types.js';
import { expectMany } from '../utils/expectations.js';

/**
 * @param {Record<string, any>} action
 * @param {Document} root
 * @return {import('../types.js').ActionResponse}
 */
export function condition(action, root = document) {
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

    // only return actions if every expectation was met (these actions will be executed by the native clients)
    const returnActions = results.every((x) => x.result === true);

    if (action.actions?.length && returnActions) {
        return new SuccessResponse({
            actionID: action.id,
            actionType: action.actionType,
            response: { actions: action.actions },
        });
    }

    return new SuccessResponse({ actionID: action.id, actionType: action.actionType, response: null });
}
