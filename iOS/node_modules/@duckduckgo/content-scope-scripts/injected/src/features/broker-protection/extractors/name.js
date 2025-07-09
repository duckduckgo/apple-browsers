// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Extractor } from '../types.js';
import { stringToList } from '../actions/extract.js';

/**
 * @implements {Extractor<string | null>}
 */
export class NameExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} _extractorParams
     */

    extract(strs, _extractorParams) {
        if (!strs[0]) return null;
        return strs[0].replace(/\n/g, ' ').trim();
    }
}

/**
 * @implements {Extractor<string[]>}
 */
export class AlternativeNamesExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     * @returns {string[]}
     */
    extract(strs, extractorParams) {
        return strs.map((x) => stringToList(x, extractorParams.separator)).flat();
    }
}
