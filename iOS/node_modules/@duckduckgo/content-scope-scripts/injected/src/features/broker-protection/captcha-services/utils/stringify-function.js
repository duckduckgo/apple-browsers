import { safeCall } from '../../utils/safe-call';

/**
 * @param {Object} params
 * @param {string} params.functionName - The name of the function
 * @param {Function} params.functionBody - The function to stringify
 * @param {Object} params.args - The arguments to pass to the function
 * @returns {string|null} - The stringified function
 */
export function stringifyFunction({ functionName, functionBody, args }) {
    return safeCall(
        () => `;(function(args) {
        ${functionBody.toString()};
        ${functionName}(args);
    })(${JSON.stringify(args)});`,
        { errorMessage: `[stringifyFunction] error stringifying function ${functionName}` },
    );
}
