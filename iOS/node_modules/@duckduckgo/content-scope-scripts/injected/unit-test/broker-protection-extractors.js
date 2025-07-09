import fc from 'fast-check';
import { cleanArray } from '../src/features/broker-protection/utils/utils.js';
import { PhoneExtractor } from '../src/features/broker-protection/extractors/phone.js';
import { ProfileUrlExtractor } from '../src/features/broker-protection/extractors/profile-url.js';

describe('individual extractors', () => {
    describe('PhoneExtractor', () => {
        it('should extract digits only', () => {
            fc.assert(
                fc.property(fc.array(fc.string()), (s) => {
                    const cleanInput = cleanArray(s);
                    const numbers = new PhoneExtractor().extract(cleanInput, {});
                    const cleanOutput = cleanArray(numbers);
                    return cleanOutput.every((num) => num.match(/^\d+$/));
                }),
            );
        });
    });
    describe('ProfileUrlExtractor', () => {
        /**
         * @typedef {import("../src/features/broker-protection/actions/extract.js").IdentifierType} IdentifierType
         */
        const testCases = [
            {
                identifierType: /** @type {IdentifierType} */ ('path'),
                // eslint-disable-next-line no-template-curly-in-string
                identifier: 'https://duckduckgo.com/my/profile/${firstName}-${lastName}/${id}',
                profileUrl: 'https://duckduckgo.com/my/profile/john-smith/223',
                expected: 'https://duckduckgo.com/my/profile/john-smith/223',
            },
            {
                identifierType: /** @type {IdentifierType} */ ('param'),
                identifier: 'pid',
                profileUrl: 'https://duckduckgo.com/my/profile?id=test',
                expected: 'https://duckduckgo.com/my/profile?id=test',
            },
            {
                identifierType: /** @type {IdentifierType} */ ('param'),
                // eslint-disable-next-line no-template-curly-in-string
                identifier: 'https://duckduckgo.com/my/profile/${firstName}-${lastName}/${id}',
                profileUrl: 'https://duckduckgo.com/my/profile/john-smith/223',
                expected: 'https://duckduckgo.com/my/profile/john-smith/223',
            },
            {
                identifierType: /** @type {IdentifierType} */ ('param'),
                identifier: 'id',
                profileUrl: 'https://duckduckgo.com/my/profile?id=test',
                expected: 'test',
            },
        ];

        testCases.forEach(({ identifierType, identifier, profileUrl, expected }) => {
            it(`should return the correct identifier when identifierType is "${identifierType}" and identifier is "${identifier}"`, () => {
                const profile = new ProfileUrlExtractor().extract([profileUrl], { identifierType, identifier });

                expect(profile?.identifier).toEqual(expected);
            });
        });
    });
});
