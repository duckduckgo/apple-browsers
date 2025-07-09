import { DDG_STATS_OTHER_COMPANY_IDENTIFIER } from './constants.js';

/**
 * Sort into descending order + place __other__ at the end.
 *
 * @import { TrackerCompany } from "../../types/new-tab"
 * @param {TrackerCompany[]} stats
 * @return {TrackerCompany[]}
 */
export function sortStatsForDisplay(stats) {
    const sorted = stats.slice().sort((a, b) => b.count - a.count);
    const other = sorted.findIndex((x) => x.displayName === DDG_STATS_OTHER_COMPANY_IDENTIFIER);
    if (other > -1) {
        const popped = sorted.splice(other, 1);
        sorted.push(popped[0]);
    }
    return sorted;
}

/**
 * @param {string} companyName
 */
export function displayNameForCompany(companyName) {
    return (
        companyName
            // remove any end sections followed by a '.' - this handles things like `Amazon.com` as a company name in the
            // tracker radar dataset
            .replace(/\.[a-z]+$/i, '')
    );
}
