import { aggregateFields, createProfile, stringValuesFromElements } from '../src/features/broker-protection/actions/extract.js';
import { cleanArray } from '../src/features/broker-protection/utils/utils.js';

describe('create profiles from extracted data', () => {
    describe('cleanArray', () => {
        it('should filter out null, undefined, and empty strings', () => {
            /**
             * @type {any[]}
             */
            const items = [
                { input: ['a', '', '  ', '    '], expected: ['a'] },
                { input: 'a', expected: ['a'] },
                { input: ['a'], expected: ['a'] },
                { input: null, expected: [] },
                { input: [], expected: [] },
                { input: ['', '    ', 'def'], expected: ['def'] },
                { input: [null], expected: [] },
                { input: [[[]]], expected: [] },
                { input: [null, '', 0, '  '], expected: [0] },
                { input: [null, '000'], expected: ['000'] },
            ];
            for (const item of items) {
                const actual = cleanArray(item.input);
                expect(actual).toEqual(item.expected);
            }
        });
    });
    it('handles combined, single strings', () => {
        const selectors = {
            name: {
                selector: '.name',
                beforeText: ',',
            },
            age: {
                selector: '.name',
                afterText: ',',
            },
        };

        const elementExamples = [
            { text: 'John smith, 39', expected: { name: 'John smith', age: '39' } },
            { text: 'John smith  , 39', expected: { name: 'John smith', age: '39' } },
            { text: 'John\nsmith  , 39', expected: { name: 'John smith', age: '39' } },
            { text: 'John\nsmith  , 39 anything', expected: { name: 'John smith', age: '39' } },
            { text: '   John smith, 39', expected: { name: 'John smith', age: '39' } },
            { text: '   John smith,39', expected: { name: 'John smith', age: '39' } },
            { text: '   John smith, ~39', expected: { name: 'John smith', age: '39' } },
            { text: 'Jane Doe, 45', expected: { name: 'Jane Doe', age: '45' } },
            { text: '   Robert Johnson,22', expected: { name: 'Robert Johnson', age: '22' } },
            { text: 'Emily Wilson , 29 ', expected: { name: 'Emily Wilson', age: '29' } },
            { text: 'Daniel Miller\n\n, 56', expected: { name: 'Daniel Miller', age: '56' } },
            { text: 'Henry White   ,46', expected: { name: 'Henry White', age: '46' } },
            { text: 'Linda Brown ~ , 35', expected: { name: 'Linda Brown ~', age: '35' } },
            { text: 'Emma Green, 30 any', expected: { name: 'Emma Green', age: '30' } },
            { text: '  Sophia Blue, 26', expected: { name: 'Sophia Blue', age: '26' } },

            // examples where age is absent, so the result should be null
            { text: 'John smith', expected: { name: 'John smith', age: null } },
            { text: 'John smith   ,   ', expected: { name: 'John smith', age: null } },
            { text: 'John smith   \n,\n   ', expected: { name: 'John smith', age: null } },
        ];

        for (const elementExample of elementExamples) {
            const elementFactory = () => {
                return [{ innerText: elementExample.text }];
            };
            const profile = createProfile(elementFactory, selectors);
            expect(profile).toEqual(elementExample.expected);
        }
    });
    it('handles multiple strings', () => {
        const elementExamples = [
            {
                selectors: {
                    alternativeNamesList: {
                        selector: 'example',
                        afterText: 'Also Known as:',
                        separator: ',',
                    },
                },
                elements: [{ innerText: 'Also Known as: John Smith, Jon Smith' }],
                expected: {
                    alternativeNamesList: ['John Smith', 'Jon Smith'],
                },
            },
            {
                selectors: {
                    alternativeNamesList: {
                        selector: 'example',
                        findElements: true,
                        afterText: 'Also Known as:',
                    },
                },
                elements: [{ innerText: 'Also Known as: John Smith' }, { innerText: 'Jon Smith' }],
                expected: {
                    alternativeNamesList: ['John Smith', 'Jon Smith'],
                },
            },
            {
                selectors: {
                    alternativeNamesList: {
                        selector: 'example',
                        findElements: true,
                        beforeText: ', ',
                    },
                },
                elements: [{ innerText: 'John Smith, 89' }, { innerText: 'Jon Smith, 78' }],
                expected: {
                    alternativeNamesList: ['John Smith', 'Jon Smith'],
                },
            },
        ];

        for (const elementExample of elementExamples) {
            const elementFactory = () => elementExample.elements;
            const profile = createProfile(elementFactory, elementExample.selectors);
            expect(profile).toEqual(elementExample.expected);
        }
    });
    it('should omit invalid addresses', () => {
        const elementExamples = [
            {
                selectors: {
                    addressCityState: {
                        selector: 'example',
                    },
                },
                elements: [{ innerText: 'anything, here' }],
                expected: {
                    addressCityState: [],
                },
            },
        ];

        for (const elementExample of elementExamples) {
            const elementFactory = () => elementExample.elements;
            const profile = createProfile(elementFactory, elementExample.selectors);
            expect(profile).toEqual(elementExample.expected);
        }
    });

    it('should omit duplicate addresses when aggregated', () => {
        const elementExamples = [
            {
                selectors: {
                    addressCityState: {
                        selector: 'example',
                        findElements: true,
                    },
                },
                elements: [{ innerText: 'Dallas, TX' }, { innerText: 'Dallas, TX' }],
                expected: {
                    addresses: [{ city: 'Dallas', state: 'TX' }],
                },
            },
        ];

        for (const elementExample of elementExamples) {
            const elementFactory = () => elementExample.elements;
            const profile = createProfile(elementFactory, elementExample.selectors);
            const aggregated = aggregateFields(profile);
            expect(aggregated.addresses).toEqual(elementExample.expected.addresses);
        }
    });

    it('should handle addressCityStateList', () => {
        const example = {
            selectors: {
                addressCityStateList: {
                    selector: 'example',
                },
            },
            elements: [{ innerText: 'Dallas, TX • The Colony, TX • Carrollton, TX • +1 more' }],
            expected: {
                addresses: [
                    { city: 'Carrollton', state: 'TX' },
                    { city: 'Dallas', state: 'TX' },
                    { city: 'The Colony', state: 'TX' },
                ],
            },
        };

        const elementFactory = () => example.elements;
        const profile = createProfile(elementFactory, /** @type {any} */ (example.selectors));
        const aggregated = aggregateFields(profile);

        expect(aggregated.addresses).toEqual(example.expected.addresses);
    });

    it('should include addresses from `addressFullList` - https://app.asana.com/0/0/1206856260863051/f', () => {
        const elementExamples = [
            {
                selectors: {
                    addressFullList: {
                        selector: 'example',
                        findElements: true,
                    },
                },
                elements: [{ innerText: '123 fake street,\nDallas, TX 75215' }, { innerText: '123 fake street,\nMiami, FL 75215' }],
                expected: {
                    addresses: [
                        { city: 'Miami', state: 'FL' },
                        { city: 'Dallas', state: 'TX' },
                    ],
                },
            },
        ];

        for (const elementExample of elementExamples) {
            const elementFactory = () => elementExample.elements;
            const profile = createProfile(elementFactory, /** @type {any} */ (elementExample.selectors));
            const aggregated = aggregateFields(profile);
            expect(aggregated.addresses).toEqual(elementExample.expected.addresses);
        }
    });

    it('should exclude common prefixes/suffixes https://app.asana.com/0/0/1206808591178551/f', () => {
        const selectors = {
            relativesList: {
                selector: 'example',
                findElements: true,
                afterText: 'AKA:',
            },
        };
        const elementFactory = (key) => {
            return {
                relativesList: [
                    { innerText: 'AKA: Jane Smith' },
                    { innerText: 'John Smith - ' },
                    { innerText: 'Jimmy Smith +1 more' },
                    { innerText: 'Jimmy Smith + 1 more' },
                    { innerText: 'Jimmy Smith +3 more like this' },
                    { innerText: 'Jill Johnson +4 more' },
                    { innerText: 'Jack Johnson - ' },
                    { innerText: 'John Smith, 39 - ' },
                    { innerText: 'John Smith, 39 years old' },
                    { innerText: 'Jimmy Smith, 39 +1 more' },
                    { innerText: 'Jimmy Smith, 39 + 1 more' },
                    { innerText: 'Jimmy Smith, 39 +3 more like this' },
                    { innerText: 'Jill Johnson, 39 +4 more' },
                    { innerText: 'Jack Johnson, 39 - ' },
                ],
            }[key];
        };
        const scraped = createProfile(elementFactory, /** @type {any} */ (selectors));
        expect(scraped).toEqual({
            relativesList: [
                'Jane Smith',
                'John Smith',
                'Jimmy Smith',
                'Jimmy Smith',
                'Jimmy Smith',
                'Jill Johnson',
                'Jack Johnson',
                'John Smith',
                'John Smith',
                'Jimmy Smith',
                'Jimmy Smith',
                'Jimmy Smith',
                'Jill Johnson',
                'Jack Johnson',
            ],
        });
    });

    it('(1) Addresses: general validation [validation] https://app.asana.com/0/0/1206808587680141/f', () => {
        const selectors = {
            name: {
                selector: 'example',
            },
            age: {
                selector: 'example',
            },
            addressCityState: {
                selector: 'example',
                findElements: true,
            },
        };
        const elementFactory = (key) => {
            return {
                name: [{ innerText: 'Shane Osbourne' }],
                age: [{ innerText: '39' }],
                addressCityState: [{ innerText: 'Dallas, TX' }, { innerText: 'anything, here' }],
            }[key];
        };
        const expected = [{ city: 'Dallas', state: 'TX' }];

        const scraped = createProfile(elementFactory, /** @type {any} */ (selectors));
        const actual = aggregateFields(scraped);
        expect(actual.addresses).toEqual(expected);
    });

    it('should sort relatives by name alphabetically', () => {
        const selectors = {
            relativesList: {
                selector: 'example',
                findElements: true,
            },
        };
        const elementFactory = (key) => {
            return {
                relativesList: [
                    { innerText: 'Dale Johnson' },
                    { innerText: 'John Smith' },
                    { innerText: 'Jimmy Smith' },
                    { innerText: 'Jill Johnson' },
                    { innerText: 'Jack Johnson' },
                ],
            }[key];
        };
        const scraped = createProfile(elementFactory, /** @type {any} */ (selectors));
        const actual = aggregateFields(scraped);

        expect(actual.relatives).toEqual(['Dale Johnson', 'Jack Johnson', 'Jill Johnson', 'Jimmy Smith', 'John Smith']);
    });

    it('should sort phone numbers numerically', () => {
        const selectors = {
            phoneList: {
                selector: 'example',
                findElements: true,
            },
        };
        const elementFactory = (key) => {
            return {
                phoneList: [
                    { innerText: '123-456-7895' },
                    { innerText: '123-456-7894' },
                    { innerText: '123-456-7892' },
                    { innerText: '123-456-7891' },
                    { innerText: '123-456-7890' },
                ],
            }[key];
        };
        const scraped = createProfile(elementFactory, /** @type {any} */ (selectors));
        const actual = aggregateFields(scraped);

        expect(actual.phoneNumbers).toEqual(['1234567890', '1234567891', '1234567892', '1234567894', '1234567895']);
    });

    it('should sort alternative names alphabetically', () => {
        const selectors = {
            alternativeNamesList: {
                selector: 'example',
                findElements: true,
            },
        };
        const elementFactory = (key) => {
            return {
                alternativeNamesList: [
                    { innerText: 'Jerry Doug' },
                    { innerText: 'Marvin Smith' },
                    { innerText: 'Roger Star' },
                    { innerText: 'Fred Firth' },
                ],
            }[key];
        };
        const scraped = createProfile(elementFactory, /** @type {any} */ (selectors));
        const actual = aggregateFields(scraped);

        expect(actual.alternativeNames).toEqual(['Fred Firth', 'Jerry Doug', 'Marvin Smith', 'Roger Star']);
    });

    it('should extract innerText by default', () => {
        const element = {
            innerText: 'John Smith, 39',
            textContent: 'Ignore me',
        };
        expect(stringValuesFromElements([element], 'testKey', { selector: 'example' })).toEqual(['John Smith, 39']);
    });

    it('should extract textElement if innerText is not present', () => {
        const element = {
            textContent: 'John Smith, 39',
        };
        expect(stringValuesFromElements([element], 'testKey', { selector: 'example' })).toEqual(['John Smith, 39']);
    });
});
