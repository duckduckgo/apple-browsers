import assert from 'node:assert';
import { test } from 'node:test';
import { urlToColor } from '../shared/getColorForString.js';
import fc from 'fast-check';

/**
 * These values were extracted from the running macOS application
 * These tests ensure our JS version matches what users have seen already in macOS
 */
const macosValues = [
    { input: 'google.pl', expected: '#ECCC7B' },
    { input: 'wikipedia.org', expected: '#DD6B4C' },
    { input: 'twitter.com', expected: '#99DB7A' },
    { input: 'icloud.com', expected: '#645468' },
    { input: 'apple.com', expected: '#855DB6' },
    { input: 'apple.com', expected: '#855DB6' },
    { input: 'polskieradio.pl', expected: '#99DB7A' },
    { input: 'example.com', expected: '#645468' },
    { input: 'google.com', expected: '#D65D62' },
    { input: 'google.pl', expected: '#ECCC7B' },
    { input: 'machars.net', expected: '#6BB4EF' },
    { input: 'badssl.com', expected: '#99DB7A' },
    { input: 'bing.com', expected: '#645468' },
    { input: 'facebook.com', expected: '#855DB6' },
    { input: 'example.com', expected: '#645468' },
    { input: 'github.com', expected: '#5E5ADB' },
    { input: 'example.com', expected: '#645468' },
    { input: 'gumroad.com', expected: '#D65D62' },
    { input: 'trainingpeaks.com', expected: '#DD6B4C' },
    { input: 'youtube.com', expected: '#727998' },
    { input: 'polskieradio.pl', expected: '#99DB7A' },
    { input: 'mbed.com', expected: '#55D388' },
];

test(`Test urlToColor on macos`, () => {
    for (const testcase of macosValues) {
        const result = urlToColor(testcase.input);
        assert.strictEqual(result, testcase.expected, `Expected "${testcase.expected}", but got "${result}"`);
    }
});

test('urlToColor never throws', () => {
    fc.assert(
        fc.property(fc.anything(), (input) => {
            assert.doesNotThrow(() => urlToColor(/** @type {any} */ (input)));
        }),
        { verbose: true },
    );
});

test('urlToColor returns string or null', () => {
    fc.assert(
        fc.property(fc.anything(), (input) => {
            const result = urlToColor(/** @type {any} */ (input));
            assert.strictEqual(
                typeof result === 'string' || result === null,
                true,
                `Expected result to be string or null, but got "${result}"`,
            );
        }),
        { verbose: true },
    );
});
