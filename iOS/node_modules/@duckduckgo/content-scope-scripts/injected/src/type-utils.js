import { toString as capturedToString } from './captured-globals.js';

/**
 * @param {unknown} input
 * @return {input is Object}
 */
export function isObject(input) {
    return capturedToString.call(input) === '[object Object]';
}

/**
 * @param {unknown} input
 * @return {input is string}
 */
export function isString(input) {
    return typeof input === 'string';
}
