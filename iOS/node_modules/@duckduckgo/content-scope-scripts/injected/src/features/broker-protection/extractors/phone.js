// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Extractor } from '../types.js';
import { stringToList } from '../actions/extract.js';

/**
 * @implements {Extractor<string[]>}
 */
export class PhoneExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
        return strs
            .map((str) => stringToList(str, extractorParams.separator))
            .flat()
            .map((str) => str.replace(/\D/g, ''));
    }
}
