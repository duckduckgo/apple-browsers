import { names } from './constants.js';

/**
 * @param {string} fullNameExtracted
 * @param {string} userFirstName
 * @param {string | null | undefined} userMiddleName
 * @param {string} userLastName
 * @param {string | null} [userSuffix]
 * @return {boolean}
 */
export function isSameName(fullNameExtracted, userFirstName, userMiddleName, userLastName, userSuffix) {
    // If there's no name on the website, then there's no way we can match it
    if (!fullNameExtracted) {
        return false;
    }

    // these fields should never be absent. If they are we cannot continue
    if (!userFirstName || !userLastName) return false;

    fullNameExtracted = fullNameExtracted.toLowerCase().trim().replace('.', '');
    userFirstName = userFirstName.toLowerCase();
    userMiddleName = userMiddleName ? userMiddleName.toLowerCase() : null;
    userLastName = userLastName.toLowerCase();
    userSuffix = userSuffix ? userSuffix.toLowerCase() : null;

    // Get a list of the user's name and nicknames / full names
    const names = getNames(userFirstName);

    for (const firstName of names) {
        // Let's check if the name matches right off the bat
        const nameCombo1 = `${firstName} ${userLastName}`;
        if (fullNameExtracted === nameCombo1) {
            return true;
        }

        // If the user didn't supply a middle name, then try to match names extracted names that
        // might include a middle name.
        if (!userMiddleName) {
            const combinedLength = firstName.length + userLastName.length;
            const matchesFirstAndLast =
                fullNameExtracted.startsWith(firstName) &&
                fullNameExtracted.endsWith(userLastName) &&
                fullNameExtracted.length > combinedLength;
            if (matchesFirstAndLast) {
                return true;
            }
        }

        // If there's a suffix, check that too
        if (userSuffix) {
            const nameCombo1WithSuffix = `${firstName} ${userLastName} ${userSuffix}`;
            if (fullNameExtracted === nameCombo1WithSuffix) {
                return true;
            }
        }

        // If the user has a name with a hyphen, we should split it on the hyphen
        // Note: They may have a last name or first name with a hyphen
        if (userLastName && userLastName.includes('-')) {
            const userLastNameOption2 = userLastName.split('-').join(' ');
            const userLastNameOption3 = userLastName.split('-').join('');
            const userLastNameOption4 = userLastName.split('-')[0];

            const comparisons = [
                `${firstName} ${userLastNameOption2}`,
                `${firstName} ${userLastNameOption3}`,
                `${firstName} ${userLastNameOption4}`,
            ];

            if (comparisons.includes(fullNameExtracted)) {
                return true;
            }
        }

        // Treat first name with the same logic as the last name
        if (userFirstName && userFirstName.includes('-')) {
            const userFirstNameOption2 = userFirstName.split('-').join(' ');
            const userFirstNameOption3 = userFirstName.split('-').join('');
            const userFirstNameOption4 = userFirstName.split('-')[0];

            const comparisons = [
                `${userFirstNameOption2} ${userLastName}`,
                `${userFirstNameOption3} ${userLastName}`,
                `${userFirstNameOption4} ${userLastName}`,
            ];

            if (comparisons.includes(fullNameExtracted)) {
                return true;
            }
        }

        // Only run this if they have a middle name
        // Note: Only do the suffix comparison if it actually exists
        if (userMiddleName) {
            const comparisons = [
                `${firstName} ${userMiddleName} ${userLastName}`,
                `${firstName} ${userMiddleName} ${userLastName} ${userSuffix}`,
                `${firstName} ${userMiddleName[0]} ${userLastName}`,
                `${firstName} ${userMiddleName[0]} ${userLastName} ${userSuffix}`,
                `${firstName} ${userMiddleName}${userLastName}`,
                `${firstName} ${userMiddleName}${userLastName} ${userSuffix}`,
            ];

            if (comparisons.includes(fullNameExtracted)) {
                return true;
            }

            // If it's a hyphenated last name, we have more to try
            if (userLastName && userLastName.includes('-')) {
                const userLastNameOption2 = userLastName.split('-').join(' ');
                const userLastNameOption3 = userLastName.split('-').join('');
                const userLastNameOption4 = userLastName.split('-')[0];

                const comparisons = [
                    `${firstName} ${userMiddleName} ${userLastNameOption2}`,
                    `${firstName} ${userMiddleName} ${userLastNameOption4}`,
                    `${firstName} ${userMiddleName[0]} ${userLastNameOption2}`,
                    `${firstName} ${userMiddleName[0]} ${userLastNameOption3}`,
                    `${firstName} ${userMiddleName[0]} ${userLastNameOption4}`,
                ];

                if (comparisons.includes(fullNameExtracted)) {
                    return true;
                }
            }

            // If it's a hyphenated name, we have more to try
            if (userFirstName && userFirstName.includes('-')) {
                const userFirstNameOption2 = userFirstName.split('-').join(' ');
                const userFirstNameOption3 = userFirstName.split('-').join('');
                const userFirstNameOption4 = userFirstName.split('-')[0];

                const comparisons = [
                    `${userFirstNameOption2} ${userMiddleName} ${userLastName}`,
                    `${userFirstNameOption3} ${userMiddleName} ${userLastName}`,
                    `${userFirstNameOption4} ${userMiddleName} ${userLastName}`,
                    `${userFirstNameOption2} ${userMiddleName[0]} ${userLastName}`,
                    `${userFirstNameOption3} ${userMiddleName[0]} ${userLastName}`,
                    `${userFirstNameOption4} ${userMiddleName[0]} ${userLastName}`,
                ];

                if (comparisons.includes(fullNameExtracted)) {
                    return true;
                }
            }
        }
    }

    return false;
}

/**
 * Given the user's provided name, look for nicknames or full names and return a list
 *
 * @param {string | null} name
 * @return {Set<string>}
 */
export function getNames(name) {
    if (!noneEmptyString(name)) {
        return new Set();
    }

    name = name.toLowerCase();
    const nicknames = names.nicknames;

    return new Set([name, ...getNicknames(name, nicknames), ...getFullNames(name, nicknames)]);
}

/**
 * Given a full name, get a list of nicknames, e.g. Gregory -> Greg
 *
 * @param {string | null} name
 * @param {Record<string, string[]>} nicknames
 * @return {Set<string>}
 */
export function getNicknames(name, nicknames) {
    const emptySet = new Set();

    if (!noneEmptyString(name)) {
        return emptySet;
    }

    name = name.toLowerCase();

    if (Object.prototype.hasOwnProperty.call(nicknames, name)) {
        return new Set(nicknames[name]);
    }

    return emptySet;
}

/**
 * Given a nickname, get a list of full names - e.g. Greg -> Gregory
 *
 * @param {string | null} name
 * @param {Record<string, string[]>} nicknames
 * @return {Set<string>}
 */
export function getFullNames(name, nicknames) {
    const fullNames = new Set();

    if (!noneEmptyString(name)) {
        return fullNames;
    }

    name = name.toLowerCase();

    for (const fullName of Object.keys(nicknames)) {
        if (nicknames[fullName].includes(name)) {
            fullNames.add(fullName);
        }
    }

    return fullNames;
}

/**
 * This will handle all none-string types like null / undefined too
 * @param {any} [input]
 * @return {input is string}
 */
function noneEmptyString(input) {
    if (typeof input !== 'string') return false;
    return input.trim().length > 0;
}
