import fc from 'fast-check';
import { describe, it } from 'node:test';
import { deepEqual } from 'node:assert/strict';
import { apply } from '../shared/translations.js';

describe('applying string replacements for translations', () => {
    it('handles empty values', () => {
        const actual = apply('');
        const expected = '';
        deepEqual(actual, expected);
    });
    it('replaces a value', () => {
        const actual = apply('ab {c}', { c: 'd' });
        const expected = 'ab d';
        deepEqual(actual, expected);
    });
    it('replaces multiple values', () => {
        const actual = apply('ab {c} {d}', { c: 'e', d: 'f' });
        const expected = 'ab e f';
        deepEqual(actual, expected);
    });
    it('ignores non-string replacements', () => {
        const actual = apply('ab {c}', { c: null });
        const expected = 'ab ';
        deepEqual(actual, expected);
    });
    it('increases string length', () => {
        {
            const actual = apply('abc', undefined, 1.5);
            const expected = 'abcab';
            deepEqual(actual, expected);
        }
        {
            const actual = apply('abc', undefined, 2);
            const expected = 'abcabc';
            deepEqual(actual, expected);
        }
    });
    it('should not throw and always return a string', { only: true }, () => {
        const subject = fc.anything();
        const textLen = fc.oneof(fc.integer({ min: 0, max: 10 }), fc.float({ min: 0, max: 10 }));
        fc.assert(
            fc.property(subject, fc.object(), textLen, (subject, replacements, textLength) => {
                try {
                    const result = apply(/** @type {any} */ (subject), replacements, textLength);
                    return typeof result === 'string';
                } catch (error) {
                    console.error(error);
                    return false;
                }
            }),
            // two failure that occurred during testing
            // { seed: 1952265913, path: "20:1:0:0:1:1:2:1:25:3:1", endOnFailure: true }
            // { seed: -458639988, path: "0:0:0:0", endOnFailure: true }
        );
    });
});
