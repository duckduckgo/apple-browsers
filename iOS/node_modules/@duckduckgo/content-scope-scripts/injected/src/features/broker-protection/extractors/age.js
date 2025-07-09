// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Extractor } from '../types.js';

/**
 * @implements {Extractor<string | null>}
 */
export class AgeExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} _extractorParams
     */

    extract(strs, _extractorParams) {
        if (!strs[0]) return null;
        return strs[0].match(/\d+/)?.[0] ?? null;
    }
}
