// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Extractor } from '../types.js';
import { stringToList } from '../actions/extract.js';

/**
 * @implements {Extractor<string[]>}
 */
export class RelativesExtractor {
    /**
     * @param {string[]} strs
     * @param {import('../actions/extract.js').ExtractorParams} extractorParams
     */
    extract(strs, extractorParams) {
        return (
            strs
                .map((x) => stringToList(x, extractorParams.separator))
                .flat()
                // for relatives, remove anything following a comma (usually 'age')
                // eg: 'John Smith, 39' -> 'John Smith'
                .map((x) => x.split(',')[0])
        );
    }
}
