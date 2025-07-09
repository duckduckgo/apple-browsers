import { describe, it } from 'node:test';
import { deepEqual } from 'node:assert/strict';
import { privacyStatsMocks } from '../mocks/privacy-stats.mocks.js';
import { sortStatsForDisplay } from '../privacy-stats.utils.js';

/**
 * @import { TrackerCompany } from "../../../types/new-tab"
 */

describe('stats re-ordering', () => {
    it('orders based on count + places __other__ at the end of the list', () => {
        /** @type {TrackerCompany[]} */
        const input = privacyStatsMocks.few.trackerCompanies;
        const expected = [
            { displayName: 'Facebook', count: 310 },
            { displayName: 'Google', count: 279 },
            { displayName: 'Amazon', count: 67 },
            { displayName: 'Google Ads', count: 2 },
            { displayName: '__other__', count: 210 },
        ];
        const actual = sortStatsForDisplay(input);
        deepEqual(actual, expected);
    });
    it('orders when other is absent', () => {
        /** @type {TrackerCompany[]} */
        const input = [
            { displayName: 'Google', count: 279 },
            { displayName: 'Google Ads', count: 2 },
            { displayName: 'Amazon', count: 67 },
            { displayName: 'Facebook', count: 310 },
        ];
        const expected = [
            { displayName: 'Facebook', count: 310 },
            { displayName: 'Google', count: 279 },
            { displayName: 'Amazon', count: 67 },
            { displayName: 'Google Ads', count: 2 },
        ];
        const actual = sortStatsForDisplay(input);
        deepEqual(actual, expected);
    });
    it('sorts a single item', () => {
        /** @type {TrackerCompany[]} */
        const input = [{ displayName: 'Google', count: 279 }];
        const expected = [{ displayName: 'Google', count: 279 }];
        const actual = sortStatsForDisplay(input);
        deepEqual(actual, expected);
    });
});
