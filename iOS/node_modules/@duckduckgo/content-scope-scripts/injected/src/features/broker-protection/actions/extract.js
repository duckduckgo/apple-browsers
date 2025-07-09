import { cleanArray, getElement, getElementMatches, getElements, sortAddressesByStateAndCity } from '../utils/utils.js'; // Assuming you have imported the address comparison function
import { ErrorResponse, ProfileResult, SuccessResponse } from '../types.js';
import { isSameAge } from '../comparisons/is-same-age.js';
import { isSameName } from '../comparisons/is-same-name.js';
import { addressMatch } from '../comparisons/address.js';
import { AgeExtractor } from '../extractors/age.js';
import { AlternativeNamesExtractor, NameExtractor } from '../extractors/name.js';
import { AddressFullExtractor, CityStateExtractor } from '../extractors/address.js';
import { PhoneExtractor } from '../extractors/phone.js';
import { RelativesExtractor } from '../extractors/relatives.js';
import { ProfileHashTransformer, ProfileUrlExtractor } from '../extractors/profile-url.js';

/**
 * Adding these types here so that we can switch to generated ones later
 * @typedef {Record<string, any>} Action
 */

/**
 * @typedef {'param'|'path'|'hash'} IdentifierType
 * @typedef {Object} ExtractProfileProperty
 * For example: {
 *   "selector": ".//div[@class='col-sm-24 col-md-8 relatives']//li"
 * }
 * @property {string} selector - xpath or css selector
 * @property {boolean} [findElements] - whether to get all occurrences of the selector
 * @property {string} [afterText] - get all text after this string
 * @property {string} [beforeText] - get all text before this string
 * @property {string} [separator] - split the text on this string
 * @property {IdentifierType} [identifierType] - the type (path/param) of the identifier
 * @property {string} [identifier] - the identifier itself (either a param name, or a templated URI)
 *
 * @typedef {Omit<ExtractProfileProperty, 'selector' | 'findElements'>} ExtractorParams
 */

/**
 * @param {Action} action
 * @param {Record<string, any>} userData
 * @param {Document | HTMLElement} root
 * @return {Promise<import('../types.js').ActionResponse>}
 */
export async function extract(action, userData, root = document) {
    const extractResult = extractProfiles(action, userData, root);

    if ('error' in extractResult) {
        return new ErrorResponse({ actionID: action.id, message: extractResult.error });
    }

    const filteredPromises = extractResult.results
        .filter((x) => x.result === true)
        .map((x) => aggregateFields(x.scrapedData))
        .map((profile) => applyPostTransforms(profile, action.profile));

    const filtered = await Promise.all(filteredPromises);

    // omit the DOM node from data transfer

    const debugResults = extractResult.results.map((result) => result.asData());

    return new SuccessResponse({
        actionID: action.id,
        actionType: action.actionType,
        response: filtered,
        meta: {
            userData,
            extractResults: debugResults,
        },
    });
}

/**
 * @param {Action} action
 * @param {Record<string, any>} userData
 * @param {Element | Document} [root]
 * @return {{error: string} | {results: ProfileResult[]}}
 */
export function extractProfiles(action, userData, root = document) {
    const profilesElementList = getElements(root, action.selector) ?? [];

    if (profilesElementList.length === 0) {
        if (!action.noResultsSelector) {
            return { error: 'no root elements found for ' + action.selector };
        }

        // Look for the Results Not Found element
        const foundNoResultsElement = getElement(root, action.noResultsSelector);

        if (!foundNoResultsElement) {
            return { error: 'no results found for ' + action.selector + ' or the no results selector ' + action.noResultsSelector };
        }
    }

    return {
        results: profilesElementList.map((element) => {
            const elementFactory = (_, value) => {
                return value?.findElements
                    ? cleanArray(getElements(element, value.selector))
                    : cleanArray(getElement(element, value.selector) || getElementMatches(element, value.selector));
            };
            const scrapedData = createProfile(elementFactory, action.profile);
            const { result, score, matchedFields } = scrapedDataMatchesUserData(userData, scrapedData);
            return new ProfileResult({
                scrapedData,
                result,
                score,
                element,
                matchedFields,
            });
        }),
    };
}

/**
 * Produces structures like this:
 *
 * {
 *   "name": "John V Smith",
 *   "alternativeNamesList": [
 *     "John Inc Smith",
 *     "John Vsmith",
 *     "John Smithl"
 *   ],
 *   "age": "97",
 *   "addressCityStateList": [
 *     {
 *       "city": "Orlando",
 *       "state": "FL"
 *     }
 *   ],
 *   "profileUrl": "https://example.com/1234"
 * }
 *
 * @param {(key: string, value: ExtractProfileProperty) => {innerText: string}[]} elementFactory
 *   a function that produces elements for a given key + ExtractProfileProperty
 * @param {Record<string, ExtractProfileProperty>} extractData
 * @return {Record<string, any>}
 */
export function createProfile(elementFactory, extractData) {
    const output = {};
    for (const [key, value] of Object.entries(extractData)) {
        if (!value?.selector) {
            output[key] = null;
        } else {
            const elements = elementFactory(key, value);

            // extract all strings first
            const evaluatedValues = stringValuesFromElements(elements, key, value);

            // clean them up - trimming, removing empties
            const noneEmptyArray = cleanArray(evaluatedValues);

            // Note: This can return any valid JSON valid, it depends on the extractor used.
            const extractedValue = extractValue(key, value, noneEmptyArray);

            // try to use the extracted value, or fall back to null
            // this allows 'extractValue' to return null|undefined
            output[key] = extractedValue || null;
        }
    }
    return output;
}

/**
 * @param {({ textContent: string } | { innerText: string })[]} elements
 * @param {string} key
 * @param {ExtractProfileProperty} extractField
 * @return {string[]}
 */
export function stringValuesFromElements(elements, key, extractField) {
    return elements.map((element) => {
        let elementValue;

        if ('innerText' in element) {
            elementValue = rules[key]?.(element) ?? element?.innerText ?? null;

            // In instances where we use the text() node test, innerText will be undefined, and we fall back to textContent
        } else if ('textContent' in element) {
            elementValue = rules[key]?.(element) ?? element?.textContent ?? null;
        }

        if (!elementValue) {
            return elementValue;
        }

        if (extractField?.afterText) {
            elementValue = elementValue?.split(extractField.afterText)[1]?.trim() || elementValue;
        }
        // there is a case where we may want to get the text "after" and "before" certain text
        if (extractField?.beforeText) {
            elementValue = elementValue?.split(extractField.beforeText)[0].trim() || elementValue;
        }

        elementValue = removeCommonSuffixesAndPrefixes(elementValue);

        return elementValue;
    });
}

/**
 * Try to filter partial data based on the user's actual profile data
 * @param {Record<string, any>} userData
 * @param {Record<string, any>} scrapedData
 * @return {{score: number, matchedFields: string[], result: boolean}}
 */
export function scrapedDataMatchesUserData(userData, scrapedData) {
    const matchedFields = [];

    // the name matching is always a *requirement*
    if (isSameName(scrapedData.name, userData.firstName, userData.middleName, userData.lastName)) {
        matchedFields.push('name');
    } else {
        return { matchedFields, score: matchedFields.length, result: false };
    }

    // if the age field was present in the scraped data, then we consider this check a *requirement*
    if (scrapedData.age) {
        if (isSameAge(scrapedData.age, userData.age)) {
            matchedFields.push('age');
        } else {
            return { matchedFields, score: matchedFields.length, result: false };
        }
    }

    const addressFields = ['addressCityState', 'addressCityStateList', 'addressFull', 'addressFullList'];

    for (const addressField of addressFields) {
        if (addressField in scrapedData) {
            if (addressMatch(userData.addresses, scrapedData[addressField])) {
                matchedFields.push(addressField);
                return { matchedFields, score: matchedFields.length, result: true };
            }
        }
    }

    if (scrapedData.phone) {
        if (userData.phone === scrapedData.phone) {
            matchedFields.push('phone');
            return { matchedFields, score: matchedFields.length, result: true };
        }
    }

    // if we get here we didn't consider it a match
    return { matchedFields, score: matchedFields.length, result: false };
}

/**
 * @param {Record<string, any>} profile
 */
export function aggregateFields(profile) {
    // addresses
    const combinedAddresses = [
        ...(profile.addressCityState || []),
        ...(profile.addressCityStateList || []),
        ...(profile.addressFullList || []),
        ...(profile.addressFull || []),
    ];
    const addressMap = new Map(combinedAddresses.map((addr) => [`${addr.city},${addr.state}`, addr]));
    const addresses = sortAddressesByStateAndCity([...addressMap.values()]);

    // phone
    const phoneArray = profile.phone || [];
    const phoneListArray = profile.phoneList || [];
    const phoneNumbers = [...new Set([...phoneArray, ...phoneListArray])].sort((a, b) => parseInt(a) - parseInt(b));

    // relatives
    const relatives = [...new Set(profile.relativesList)].sort();

    // aliases
    const alternativeNames = [...new Set(profile.alternativeNamesList)].sort();

    return {
        name: profile.name,
        alternativeNames,
        age: profile.age,
        addresses,
        phoneNumbers,
        relatives,
        ...profile.profileUrl,
    };
}

/**
 * Example input to this:
 *
 * ```json
 * {
 *   "key": "age",
 *   "value": {
 *     "selector": ".//div[@class='col-md-8']/div[2]"
 *   },
 *   "elementValues": ["Age 71"]
 * }
 * ```
 *
 * @param {string} outputFieldKey
 * @param {ExtractProfileProperty} extractorParams
 * @param {string[]} elementValues
 * @return {any}
 */
export function extractValue(outputFieldKey, extractorParams, elementValues) {
    switch (outputFieldKey) {
        case 'age':
            return new AgeExtractor().extract(elementValues, extractorParams);
        case 'name':
            return new NameExtractor().extract(elementValues, extractorParams);

        // all addresses are processed the same way
        case 'addressFull':
        case 'addressFullList':
            return new AddressFullExtractor().extract(elementValues, extractorParams);
        case 'addressCityState':
        case 'addressCityStateList':
            return new CityStateExtractor().extract(elementValues, extractorParams);

        case 'alternativeNamesList':
            return new AlternativeNamesExtractor().extract(elementValues, extractorParams);
        case 'relativesList':
            return new RelativesExtractor().extract(elementValues, extractorParams);
        case 'phone':
        case 'phoneList':
            return new PhoneExtractor().extract(elementValues, extractorParams);
        case 'profileUrl':
            return new ProfileUrlExtractor().extract(elementValues, extractorParams);
    }
    return null;
}

/**
 * A list of transforms that should be applied to the profile after extraction/aggregation
 *
 * @param {Record<string, any>} profile
 * @param {Record<string, ExtractProfileProperty>} params
 * @return {Promise<Record<string, any>>}
 */
async function applyPostTransforms(profile, params) {
    /** @type {import("../types.js").AsyncProfileTransform[]} */
    const transforms = [
        // creates a hash if needed
        new ProfileHashTransformer(),
    ];

    let output = profile;
    for (const knownTransform of transforms) {
        output = await knownTransform.transform(output, params);
    }

    return output;
}

/**
 * @param {string} inputList
 * @param {string} [separator]
 * @return {string[]}
 */
export function stringToList(inputList, separator) {
    const defaultSeparator = /[|\n•·]/;
    return cleanArray(inputList.split(separator || defaultSeparator));
}

// For extraction
const rules = {
    profileUrl: function (link) {
        return link?.href ?? null;
    },
};

/**
 * Remove common prefixes and suffixes such as
 *
 * - AKA: <value>
 * - <value> + 1 more
 * - <value> -
 *
 * @param {string} elementValue
 * @return {string}
 */
function removeCommonSuffixesAndPrefixes(elementValue) {
    const regexes = [
        // match text such as +3 more when it appears at the end of a string
        /\+\s*\d+.*$/,
    ];
    // strings that are always safe to remove from the start
    const startsWith = [
        'Associated persons:',
        'AKA:',
        'Known as:',
        'Also known as:',
        'Has lived in:',
        'Used to live:',
        'Used to live in:',
        'Lives in:',
        'Related to:',
        'No other aliases.',
        'RESIDES IN',
    ];

    // strings that are always safe to remove from the end
    const endsWith = [' -', 'years old'];

    for (const regex of regexes) {
        elementValue = elementValue.replace(regex, '').trim();
    }
    for (const prefix of startsWith) {
        if (elementValue.startsWith(prefix)) {
            elementValue = elementValue.slice(prefix.length).trim();
        }
    }
    for (const suffix of endsWith) {
        if (elementValue.endsWith(suffix)) {
            elementValue = elementValue.slice(0, 0 - suffix.length).trim();
        }
    }

    return elementValue;
}
