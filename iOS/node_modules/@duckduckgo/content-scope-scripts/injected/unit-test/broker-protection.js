import fc from 'fast-check';
import { isSameAge } from '../src/features/broker-protection/comparisons/is-same-age.js';
import { getNicknames, getFullNames, isSameName, getNames } from '../src/features/broker-protection/comparisons/is-same-name.js';
import { stringToList, extractValue } from '../src/features/broker-protection/actions/extract.js';
import { addressMatch } from '../src/features/broker-protection/comparisons/address.js';
import { replaceTemplatedUrl } from '../src/features/broker-protection/actions/build-url.js';
import { processTemplateStringWithUserData } from '../src/features/broker-protection/actions/build-url-transforms.js';
import { names } from '../src/features/broker-protection/comparisons/constants.js';
import { generateRandomInt, hashObject, sortAddressesByStateAndCity } from '../src/features/broker-protection/utils/utils.js';
import { generatePhoneNumber, generateZipCode, generateStreetAddress } from '../src/features/broker-protection/actions/generators.js';
import { CityStateExtractor } from '../src/features/broker-protection/extractors/address.js';
import { ProfileHashTransformer } from '../src/features/broker-protection/extractors/profile-url.js';
import { getComparisonFunction } from '../src/features/broker-protection/actions/click.js';
import { isElementType } from '../src/features/broker-protection/captcha-services/utils/element.js';

describe('Actions', () => {
    describe('extract', () => {
        describe('isSameAge', () => {
            it('evaluate as the same as if the age is within 2 years', () => {
                expect(isSameAge(40, 41)).toBe(true);
            });

            it('evaluate as the same as if the age is within 2 years and given as a string', () => {
                expect(isSameAge(40, '41')).toBe(true);
            });

            it('does not evaluate as the same as if the age is not within 2 years', () => {
                expect(isSameAge(40, 44)).toBe(false);
            });

            it('does not evaluate as the same age if one is not a number', () => {
                expect(isSameAge(40, 'John Smith')).toBe(false);
            });
        });

        describe('getNames', () => {
            it('should return an empty set if the name is an empty string', () => {
                expect(Array.from(getNames(' '))).toEqual([]);
                expect(Array.from(getNames(''))).toEqual([]);
            });

            it('should return just name if there are no nicknames or full names', () => {
                expect(Array.from(getNames('J-Breeze')));
            });

            it('should return the name along with nicknames and full names if present', () => {
                expect(Array.from(getNames('Greg')).sort()).toEqual(['greg', 'gregory']);
                expect(Array.from(getNames('Gregory')).sort()).toEqual(['greg', 'gregory']);
            });
        });

        describe('getNicknames', () => {
            it('should return nicknames for a name in our nickname list', () => {
                expect(Array.from(getNicknames('Jon', names.nicknames))).toEqual(['john', 'johnny', 'jonny', 'jonnie']);
            });

            it('should return an empty set if the name has no nicknames', () => {
                expect(Array.from(getNicknames('J-Breeze', names.nicknames))).toEqual([]);
            });
        });

        describe('getFullNames', () => {
            it('should return a full name given a nickname in our list', () => {
                expect(Array.from(getFullNames('Greg', names.nicknames))).toEqual(['gregory']);
            });

            it('should return as many full names as are applicable for the nickname', () => {
                expect(Array.from(getFullNames('Kate', names.nicknames))).toEqual([
                    'katelin',
                    'katelyn',
                    'katherine',
                    'kathryn',
                    'katia',
                    'katy',
                ]);
            });

            it('should return an empty set if the nickname has no full names', () => {
                expect(Array.from(getFullNames('J-Breeze, names.nicknames', names.nicknames))).toEqual([]);
            });
        });

        describe('extractValue', () => {
            it('should convert newlines to spaces in names', () => {
                expect(extractValue('name', { selector: 'example' }, ['John\nSmith'])).toEqual('John Smith');
                expect(extractValue('name', { selector: 'example' }, ['John\nT\nSmith'])).toEqual('John T Smith');
            });
        });

        describe('isSameName', () => {
            const userName = {
                firstName: 'Jon',
                middleName: 'Andrew',
                lastName: 'Smith',
                suffix: null,
            };

            it('should match if exact match', () => {
                expect(isSameName('Jon Smith', userName.firstName, userName.middleName, userName.lastName)).toBe(true);
            });

            it('should match if nickname is given', () => {
                expect(isSameName('Jonathan Smith', userName.firstName, userName.middleName, userName.lastName)).toBe(true);
            });

            it('should match middle name', () => {
                expect(isSameName('Jon Andrew Smith', userName.firstName, userName.middleName, userName.lastName)).toBe(true);
            });

            it('should match if middle name is missing from user data but included in scraped data', () => {
                expect(isSameName('Jon A Smith', userName.firstName, null, userName.lastName)).toBe(true);
                expect(isSameName('Jon Andrew Smith', userName.firstName, null, userName.lastName)).toBe(true);
            });
            it('property testing isSameName -> boolean', () => {
                fc.assert(
                    fc.property(
                        fc.string(),
                        fc.string(),
                        fc.option(fc.string()),
                        fc.string(),
                        fc.option(fc.string()),
                        (fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix) => {
                            const result = isSameName(fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix);
                            expect(typeof result).toBe('boolean');
                        },
                    ),
                );
            });
            it('property testing isSameName -> boolean (seed 1)', () => {
                // Got TypeError: object is not iterable (cannot read property Symbol(Symbol.iterator))
                // when doing if (nicknames[name])
                fc.assert(
                    fc.property(
                        fc.string(),
                        fc.string(),
                        fc.option(fc.string()),
                        fc.string(),
                        fc.option(fc.string()),
                        (fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix) => {
                            const result = isSameName(fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix);
                            expect(typeof result).toBe('boolean');
                        },
                    ),
                    { seed: 203542789, path: '70:1:0:0:1:85:86:85:86:86', endOnFailure: true },
                );
            });
        });

        describe('ProfileHashTransformer', () => {
            /**
             * @typedef {import("../src/features/broker-protection/actions/extract.js").IdentifierType} IdentifierType
             */
            it('Should return the profile unchanged if profileUrl is not present', async () => {
                const profile = {
                    firstName: 'John',
                    lastName: 'Doe',
                };

                const generatedProfile = await new ProfileHashTransformer().transform(profile, {});
                expect(generatedProfile).toEqual(profile);
            });

            it('Should return the profile unchanged if identifierType is not set to hash', async () => {
                const profile = {
                    firstName: 'John',
                    lastName: 'Doe',
                };

                const params = {
                    profileUrl: {
                        identifierType: /** @type {IdentifierType} */ ('param'),
                    },
                };

                const generatedProfile = await new ProfileHashTransformer().transform(profile, params);
                expect(generatedProfile).toEqual(profile);
            });

            it('Should return a profile with a hash in the identifier if the identifierType is set to hash', async () => {
                const profile = {
                    firstName: 'John',
                    lastName: 'Doe',
                };

                const params = {
                    profileUrl: {
                        identifierType: /** @type {IdentifierType} */ ('hash'),
                    },
                };

                const generatedProfile = await new ProfileHashTransformer().transform(profile, params);
                expect(generatedProfile.identifier).toMatch(/^[0-9a-f]{40}$/);
            });
        });

        describe('get correct city state combos from list', () => {
            const cityStateLists = ['Chicago IL, River Forest IL, Forest Park IL, Oak Park IL'];
            const separator = ',';

            it('should match when city/state is the same', () => {
                for (const cityStateList of cityStateLists) {
                    const list = stringToList(cityStateList, separator);
                    expect(list).toEqual(['Chicago IL', 'River Forest IL', 'Forest Park IL', 'Oak Park IL']);
                    const result = new CityStateExtractor().extract(list, {});
                    expect(result).toEqual([
                        { city: 'Chicago', state: 'IL' },
                        { city: 'River Forest', state: 'IL' },
                        { city: 'Forest Park', state: 'IL' },
                        { city: 'Oak Park', state: 'IL' },
                    ]);
                }
            });
        });

        describe('get correct city state combo from a string', () => {
            it('should successfully extract the city/state when a zip code is included', () => {
                const cityStateZipList = [
                    'Chicago IL 60611',
                    'Chicago IL   60611',
                    'River Forest IL 60305-1243',
                    'Forest Park IL, 60130-1234',
                    'Oak Park IL, 60302',
                ];

                const result = new CityStateExtractor().extract(cityStateZipList, {});

                expect(result).toEqual([
                    { city: 'Chicago', state: 'IL' },
                    { city: 'Chicago', state: 'IL' },
                    { city: 'River Forest', state: 'IL' },
                    { city: 'Forest Park', state: 'IL' },
                    { city: 'Oak Park', state: 'IL' },
                ]);
            });
        });

        describe('get correct city state combos from malformedlist', () => {
            const malformedCityStateList = ['Chicago IL, River Forest IL, Fores...'];
            const separator = ',';
            it('shouldshow partial address', () => {
                for (const cityStateList of malformedCityStateList) {
                    const list = stringToList(cityStateList, separator);
                    expect(list).toEqual(['Chicago IL', 'River Forest IL', 'Fores...']);
                    const result = new CityStateExtractor().extract(list, {});
                    expect(result).toEqual([
                        { city: 'Chicago', state: 'IL' },
                        { city: 'River Forest', state: 'IL' },
                    ]);
                }
            });
        });

        describe('get correct city state combos with separator', () => {
            const cityStateList = [
                {
                    listString: 'Chicago IL\nRiver Forest IL\nForest Park IL\nOak Park IL',
                    separator: '\n',
                    list: ['Chicago IL', 'River Forest IL', 'Forest Park IL', 'Oak Park IL'],
                },
                {
                    listString: 'Chicago, IL\nRiver Forest, IL\nForest Park, IL\nOak Park, IL',
                    separator: '\n',
                    list: ['Chicago, IL', 'River Forest, IL', 'Forest Park, IL', 'Oak Park, IL'],
                },
                {
                    listString: 'Chicago IL | River Forest IL | Forest Park IL | Oak Park IL',
                    separator: '|',
                    list: ['Chicago IL', 'River Forest IL', 'Forest Park IL', 'Oak Park IL'],
                },
                {
                    listString: 'Chicago, IL | River Forest, IL | Forest Park, IL | Oak Park, IL',
                    separator: '|',
                    list: ['Chicago, IL', 'River Forest, IL', 'Forest Park, IL', 'Oak Park, IL'],
                },
                {
                    listString: 'Chicago, IL • River Forest, IL • Forest Park, IL • Oak Park, IL',
                    separator: '•',
                    list: ['Chicago, IL', 'River Forest, IL', 'Forest Park, IL', 'Oak Park, IL'],
                },
                {
                    listString: 'Chicago IL • River Forest IL • Forest Park IL • Oak Park IL',
                    separator: '•',
                    list: ['Chicago IL', 'River Forest IL', 'Forest Park IL', 'Oak Park IL'],
                },
                {
                    listString: 'Chicago IL   ·   River Forest IL   ·   Forest Park IL   ·   Oak Park IL',
                    list: ['Chicago IL', 'River Forest IL', 'Forest Park IL', 'Oak Park IL'],
                },
            ];
            it('should get correct city state with separator', () => {
                for (const item of cityStateList) {
                    const list = stringToList(item.listString, item.separator);
                    expect(list).toEqual(item.list);

                    const result = new CityStateExtractor().extract(list, {});
                    expect(result).toEqual([
                        { city: 'Chicago', state: 'IL' },
                        { city: 'River Forest', state: 'IL' },
                        { city: 'Forest Park', state: 'IL' },
                        { city: 'Oak Park', state: 'IL' },
                    ]);
                }
            });
        });

        describe('Address Matching', () => {
            const userData = {
                names: [
                    {
                        firstName: 'John',
                        middleName: null,
                        lastName: 'Smith',
                    },
                ],
                userAge: '40',
                addresses: [
                    {
                        addressLine1: '123 Fake St',
                        city: 'Chicago',
                        state: 'IL',
                        zip: '60602',
                    },
                ],
            };
            describe('matchAddressFromAddressListCityState', () => {
                it('should match when city/state is present', () => {
                    expect(addressMatch(userData.addresses, [{ city: 'chicago', state: 'il' }])).toBe(true);
                });

                it('should not match when city/state is not present', () => {
                    expect(addressMatch(userData.addresses, [{ city: 'los angeles', state: 'ca' }])).toBe(false);
                });
            });
        });
    });

    describe('buildUrl', () => {
        const userData = {
            firstName: 'John',
            lastName: 'Smith',
            city: 'Chicago',
            state: 'IL',
            age: '24',
        };

        const userData2 = {
            firstName: 'John',
            lastName: 'Smith',
            city: 'West Montego',
            state: 'NY',
            age: '24',
        };

        it('should build url without params', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    url: 'https://example.com/optout',
                },
                userData,
            );
            expect(result).toEqual({ url: 'https://example.com/optout' });
        });

        it('should build url when given valid data from path segments', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/${firstName}-${lastName}/a/b/c/search?state=${state}&city=${city|hyphenated}&fage=${age}',
                },
                userData,
            );
            expect(result).toEqual({ url: 'https://example.com/profile/John-Smith/a/b/c/search?state=il&city=Chicago&fage=24' });
        });

        it('should handle url encodings', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    url: 'https://example.com/name/$%7BfirstName%7Cdowncase%7D-$%7BlastName%7Cdowncase%7D/$%7Bcity%7Cdowncase%7D-$%7Bstate%7CstateFull%7Cdowncase%7D?age=$%7Bage%7D',
                },
                userData,
            );
            expect(result).toEqual({ url: 'https://example.com/name/john-smith/chicago-illinois?age=24' });
        });

        it('should build url when given valid data from path segments with modifiers path and url', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/${firstName|downcase}-${lastName|downcase}/a/b/c/search?state=${state|downcase}&city=${city|downcase}&fage=${age}',
                },
                userData,
            );
            expect(result).toEqual({ url: 'https://example.com/profile/john-smith/a/b/c/search?state=il&city=chicago&fage=24' });
        });

        it('should build url when given valid data from url-search param segments', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/a/b/c/search?name=${firstName}-${lastName}&other=foobar',
                },
                userData,
            );
            expect(result).toEqual({ url: 'https://example.com/profile/a/b/c/search?name=John-Smith&other=foobar' });
        });

        it('should build url when given valid data', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|hyphenated}&fage=${age}',
                },
                userData,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=il&city=Chicago&fage=24' });
        });

        it('should build hyphenated url when given hyphenated city', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|hyphenated}&fage=${age}',
                },
                userData2,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=ny&city=West-Montego&fage=24' });
        });

        it('should build downcased hyphenated url when given a downcased hyphenated city', () => {
            const result = replaceTemplatedUrl(
                {
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|downcase|hyphenated}&fage=${age}',
                },
                userData2,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=ny&city=west-montego&fage=24' });
        });

        it('should build downcased hyphenated url when given a downcased hyphenated city in a different order', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|hyphenated|downcase}&fage=${age}',
                },
                userData2,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=ny&city=west-montego&fage=24' });
        });

        it('should build downcased snakecase url when given a downcased snakecase city', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|snakecase|downcase}&fage=${age}',
                },
                userData2,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=ny&city=west_montego&fage=24' });
        });

        it('should support value substitution via defaultIfEmpty:<value>', () => {
            const testCases = [
                {
                    // eslint-disable-next-line no-template-curly-in-string
                    input: 'https://example.com/a/${middleName|defaultIfEmpty:~}/b',
                    expected: 'https://example.com/a/~/b',
                    data: userData2,
                },
                {
                    // eslint-disable-next-line no-template-curly-in-string
                    input: 'https://example.com/a/${middleName|downcase|defaultIfEmpty:anything}/b',
                    expected: 'https://example.com/a/anything/b',
                    data: userData2,
                },
                {
                    // eslint-disable-next-line no-template-curly-in-string
                    input: 'https://example.com/a/${middleName|downcase|defaultIfEmpty:anything}/b',
                    expected: 'https://example.com/a/kittie/b',
                    data: { ...userData2, middleName: 'Kittie' },
                },
            ];
            for (const testCase of testCases) {
                const result = replaceTemplatedUrl(
                    {
                        id: 0,
                        url: testCase.input,
                    },
                    testCase.data,
                );
                expect(result).toEqual({ url: testCase.expected });
            }
        });

        it('should build hyphenated url when given hyphenated state', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state|stateFull|hyphenated}&city=${city}&fage=${age}',
                },
                userData2,
            );

            expect(result).toEqual({
                url: 'https://example.com/profile/search?fname=John&lname=Smith&state=New-York&city=West+Montego&fage=24',
            });
        });

        it('should build url when given valid data and age range', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    // eslint-disable-next-line no-template-curly-in-string
                    url: 'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city}&fage=${age|ageRange}',
                    ageRange: ['18-30', '31-40', '41-50'],
                },
                userData,
            );

            expect(result).toEqual({ url: 'https://example.com/profile/search?fname=John&lname=Smith&state=il&city=Chicago&fage=18-30' });
        });

        it('should error when given an invalid action', () => {
            const result = replaceTemplatedUrl(
                {
                    id: 0,
                    url: null,
                },
                userData,
            );

            expect(result).toEqual({ error: 'Error: No url provided.' });
        });

        it('should accept any inputs and not crash', () => {
            fc.assert(
                fc.property(
                    fc.oneof(
                        fc.anything(),
                        fc.record({
                            url: fc.anything(),
                        }),
                    ),
                    fc.oneof(fc.anything(), fc.dictionary(fc.string(), fc.oneof(fc.string(), fc.integer(), fc.boolean()))),
                    (action, userData) => {
                        const result = replaceTemplatedUrl(action, userData);
                        expect('url' in result || 'error' in result);
                        if ('error' in result) {
                            expect(typeof result.error).toEqual('string');
                        }
                        if ('url' in result) {
                            const url = new URL(result.url);
                            expect(url).toBeDefined();
                        }
                    },
                ),
            );
        });

        it('should template the url with random inputs and produce a valid URL', () => {
            fc.assert(
                fc.property(
                    fc.record({
                        url: fc.constant(
                            // eslint-disable-next-line no-template-curly-in-string
                            'https://example.com/profile/search?fname=${firstName}&lname=${lastName}&state=${state}&city=${city|hyphenated}&fage=${age}',
                        ),
                    }),
                    fc.record({
                        firstName: fc.string(),
                        lastName: fc.string(),
                        city: fc.string(),
                        state: fc.string(),
                        age: fc.oneof(fc.string(), fc.integer()),
                    }),
                    (action, userData) => {
                        const result = replaceTemplatedUrl(action, userData);
                        expect('url' in result || 'error' in result);
                        if ('url' in result) {
                            const url = new URL(result.url);
                            expect(url).toBeDefined();
                        }
                    },
                ),
            );
        });
        it('should test the regex replacer with random values', () => {
            const variable = fc.string().map((randomMiddle) => {
                return '${' + randomMiddle + '}';
            });

            const padded = variable.map((randomMiddle) => {
                return '--' + randomMiddle + '--';
            });

            fc.assert(
                fc.property(
                    padded,
                    fc.object(),
                    fc.dictionary(fc.string(), fc.oneof(fc.string(), fc.integer())),
                    (input, action, userData) => {
                        const output = processTemplateStringWithUserData(input, /** @type {any} */ (action), userData);
                        expect(typeof output).toEqual('string');
                    },
                ),
            );
        });
    });

    describe('click', () => {
        it('should return the appropriate comparison function for a valid comparator', () => {
            const areEqual = getComparisonFunction('=');
            expect(areEqual(5, 5)).toBe(true);

            const areNotEqual = getComparisonFunction('!==');
            expect(areNotEqual(6, 5)).toBe(true);

            const isLessThan = getComparisonFunction('<');
            expect(isLessThan(5, 6)).toBe(true);

            const isLessThanOrEqualTo = getComparisonFunction('<=');
            expect(isLessThanOrEqualTo(6, 6)).toBe(true);

            const isMoreThan = getComparisonFunction('>');
            expect(isMoreThan(7, 6)).toBe(true);

            const isMoreThanOrEqualTo = getComparisonFunction('>=');
            expect(isMoreThanOrEqualTo(7, 7)).toBe(true);
        });

        it('should return an error for an invalid comparator', () => {
            expect(() => getComparisonFunction('!!')).toThrow();
        });
    });
});

describe('generators', () => {
    describe('generateRandomPhoneNumber', () => {
        it('generates a string of integers of an appropriate size', () => {
            const phoneNumber = generatePhoneNumber();

            expect(typeof phoneNumber).toEqual('string');
            expect(phoneNumber.length).toBe(10);
            expect(phoneNumber).toMatch(/^\d{10}$/);
        });
    });
    describe('generateZipCode', () => {
        it('generates a string of integers of an appropriate size', () => {
            const zipCode = generateZipCode();

            expect(typeof zipCode).toEqual('string');
            expect(zipCode.length).toBe(5);
            expect(zipCode).toMatch(/^\d{5}$/);
        });
    });
    describe('generateStreetAddress', () => {
        it('generates a string of integers of an appropriate size', () => {
            Array.from({ length: 30 }).forEach(() => {
                const streetAddress = generateStreetAddress();
                expect(typeof streetAddress).toEqual('string');
                expect(streetAddress).toMatch(/^\d+ [A-Za-z]+(?: [A-Za-z]+)?$/);
            });
        });
    });
});

describe('captcha-services', () => {
    describe('utils', () => {
        describe('isElementType', () => {
            it('should return true for single valid element type', () => {
                const type = 'img';
                const element = /** @type {HTMLElement} */ ({ tagName: type });
                expect(isElementType(element, type)).toBe(true);
            });

            it('should return true for multiple valid element types', () => {
                const validElementTypes = ['input', 'textarea', 'img', 'svg'];
                const type = 'svg';
                const element = /** @type {HTMLElement} */ ({ tagName: type });
                expect(isElementType(element, validElementTypes)).toBe(true);
            });

            it('should return false for invalid element types', () => {
                const validElementTypes = ['input', 'textarea', 'img', 'svg'];
                const type = 'div';
                const element = /** @type {HTMLElement} */ ({ tagName: type });
                expect(isElementType(element, validElementTypes)).toBe(false);
            });
        });
    });
});

describe('utils', () => {
    describe('generateRandomInt', () => {
        it('generates an integers between the min and max values', () => {
            fc.assert(
                fc.property(fc.integer(), fc.integer(), (a, b) => {
                    const min = Math.min(a, b);
                    const max = Math.max(a, b);

                    const result = generateRandomInt(min, max);

                    return Number.isInteger(result) && result >= min && result <= max;
                }),
            );
        });
    });

    describe('generateIdFromProfile', () => {
        it('generates a hash from a profile', async () => {
            const profile = {
                firstName: 'John',
                lastName: 'Doe',
            };

            const result = await hashObject(profile);

            expect(typeof result).toEqual('string');
            expect(result.length).toBe(40);
            expect(result).toMatch(/^[0-9a-f]{40}$/);
        });

        it('generates a stable hash from a profile', async () => {
            const profile = {
                firstName: 'John',
                lastName: 'Doe',
            };

            const originalResult = await hashObject(profile);

            profile.middleName = 'David';

            const updatedResult = await hashObject(profile);
            expect(originalResult).not.toEqual(updatedResult);

            delete profile.middleName;

            const finalResult = await hashObject(profile);
            expect(finalResult).toEqual(originalResult);
        });
    });

    describe('sortAddressesByStateAndCity', () => {
        it('sorts addresses by state and city', () => {
            const addresses = [
                {
                    city: 'Houston',
                    state: 'TX',
                },
                {
                    city: 'Ontario',
                    state: 'CA',
                },
                {
                    city: 'Dallas',
                    state: 'TX',
                },
            ];

            const result = sortAddressesByStateAndCity(addresses);

            expect(result).toEqual([
                {
                    city: 'Ontario',
                    state: 'CA',
                },
                {
                    city: 'Dallas',
                    state: 'TX',
                },
                {
                    city: 'Houston',
                    state: 'TX',
                },
            ]);
        });
    });
});
