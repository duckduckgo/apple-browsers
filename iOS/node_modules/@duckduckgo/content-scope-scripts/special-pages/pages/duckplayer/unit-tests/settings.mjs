import { describe, it } from 'node:test';
import { deepEqual } from 'node:assert/strict';
import { Settings } from '../app/settings.js';

describe('parses settings', () => {
    it('handles disabled custom error schema', () => {
        const settings = new Settings({
            customError: {
                state: 'disabled',
            },
        });
        const expected = {
            state: 'disabled',
        };

        deepEqual(settings.customError, expected);
    });
    it('handles old custom error schema', () => {
        const settings = new Settings({
            customError: {
                state: 'enabled',
                signInRequiredSelector: 'div',
            },
        });
        const expected = {
            state: 'enabled',
            settings: {
                signInRequiredSelector: 'div',
            },
        };

        deepEqual(settings.customError, expected);
    });
    it('handles new custom error schema', () => {
        const settings = new Settings({
            customError: {
                state: 'enabled',
                settings: {
                    signInRequiredSelector: 'div',
                },
            },
        });
        const expected = {
            state: 'enabled',
            settings: {
                signInRequiredSelector: 'div',
            },
        };

        deepEqual(settings.customError, expected);
    });
    it('handles custom error enabled without settings', () => {
        const settings = new Settings({
            customError: {
                state: 'enabled',
            },
        });
        const expected = {
            state: 'enabled',
            settings: {},
        };

        deepEqual(settings.customError, expected);
    });
    it('handles malformed custom error schema', () => {
        const settings = new Settings({
            customError: {
                // @ts-expect-error - Malformed object on purpose
                status: 'enabled',
            },
        });
        const expected = {
            state: 'disabled',
        };

        deepEqual(settings.customError, expected);
    });
});
