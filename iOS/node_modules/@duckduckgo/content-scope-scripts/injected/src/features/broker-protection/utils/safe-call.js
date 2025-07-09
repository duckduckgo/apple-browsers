import { PirError } from '../types';

/**
 * @template T
 * @param {function(): T} fn - The function to call safely
 * @param {object} [options]
 * @param {string} [options.errorMessage] - The error message to log
 * @returns {T|null} - The result of the function call, or null if an error occurred
 */
export function safeCall(fn, { errorMessage } = {}) {
    try {
        return fn();
    } catch (e) {
        console.error(errorMessage ?? '[safeCall] Error:', e);
        // TODO fire pixel
        return null;
    }
}

/**
 * @template T
 * @param {function(): T} fn - The function to call safely
 * @param {object} [options]
 * @param {string} [options.errorMessage] - The error message to log
 * @returns {T|PirError} - The result of the function call, or an error response if an error occurred
 */
export function safeCallWithError(fn, { errorMessage } = {}) {
    const message = errorMessage ?? '[safeCallWithError] Error';
    return safeCall(fn, { errorMessage: message }) ?? PirError.create(message);
}
