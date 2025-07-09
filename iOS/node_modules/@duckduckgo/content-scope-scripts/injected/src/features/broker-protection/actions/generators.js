import { generateRandomInt } from '../utils/utils.js';

export function generatePhoneNumber() {
    /**
     * 3 digits, 2-8, last two digits technically can't end in two 1s, but we'll ignore that requirement
     * Source: https://math.stackexchange.com/questions/920972/how-many-different-phone-numbers-are-possible-within-an-area-code/1115411#1115411
     */
    const areaCode = generateRandomInt(200, 899).toString();

    // 555-0100 through 555-0199 are for fictional use (https://en.wikipedia.org/wiki/555_(telephone_number)#Fictional_usage)
    const exchangeCode = '555';
    const lineNumber = generateRandomInt(100, 199).toString().padStart(4, '0');

    return `${areaCode}${exchangeCode}${lineNumber}`;
}

export function generateZipCode() {
    const zipCode = generateRandomInt(10000, 99999).toString();
    return zipCode;
}

export function generateStreetAddress() {
    const streetDigits = generateRandomInt(1, 5);
    const streetNumber = generateRandomInt(2, streetDigits * 1000);
    const streetNames = [
        'Main',
        'Elm',
        'Maple',
        'Oak',
        'Pine',
        'Cedar',
        'Hill',
        'Lake',
        'Sunset',
        'Washington',
        'Lincoln',
        'Marshall',
        'Spring',
        'Ridge',
        'Valley',
        'Meadow',
        'Forest',
    ];
    const streetName = streetNames[generateRandomInt(0, streetNames.length - 1)];
    const suffixes = ['', 'St', 'Ave', 'Blvd', 'Rd', 'Ct', 'Dr', 'Ln', 'Pkwy', 'Pl', 'Ter', 'Way'];
    const suffix = suffixes[generateRandomInt(0, suffixes.length - 1)];

    return `${streetNumber} ${streetName}${suffix ? ' ' + suffix : ''}`;
}
