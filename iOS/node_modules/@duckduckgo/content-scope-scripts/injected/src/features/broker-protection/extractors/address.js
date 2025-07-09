// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Extractor } from '../types.js';
import { stringToList } from '../actions/extract.js';
import parseAddress from 'parse-address';
import { states } from '../comparisons/constants.js';

/**
 * @implements {Extractor<{city:string; state: string|null}[]>}
 */
export class CityStateExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
        const cityStateList = strs.map((str) => stringToList(str, extractorParams.separator)).flat();
        return getCityStateCombos(cityStateList);
    }
}

/**
 * @implements {Extractor<{city:string; state: string|null}[]>}
 */
export class AddressFullExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
        return (
            strs
                .map((str) => str.replace('\n', ' '))
                .map((str) => stringToList(str, extractorParams.separator))
                .flat()
                .map((str) => parseAddress.parseLocation(str) || {})
                // at least 'city' is required.
                .filter((parsed) => Boolean(parsed?.city))
                .map((addr) => {
                    return { city: addr.city, state: addr.state || null };
                })
        );
    }
}

/**
 * @param {string[]} inputList
 * @return {{ city: string, state: string|null }[] }
 */
function getCityStateCombos(inputList) {
    const output = [];
    for (let item of inputList) {
        let words;
        // Strip out the zip code since we're only interested in city/state here.
        item = item.replace(/,?\s*\d{5}(-\d{4})?/, '');

        // Replace any commas at the end of the string that could confuse the city/state split.
        item = item.replace(/,$/, '');

        if (item.includes(',')) {
            words = item.split(',').map((item) => item.trim());
        } else {
            words = item.split(' ').map((item) => item.trim());
        }
        // we are removing this partial city/state combos at the end (i.e. Chi...)
        if (words.length === 1) {
            continue;
        }

        const state = words.pop();
        const city = words.join(' ');

        // exclude invalid states
        if (state && !Object.keys(states).includes(state.toUpperCase())) {
            continue;
        }

        output.push({ city, state: state || null });
    }
    return output;
}
