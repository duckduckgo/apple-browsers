/**
 * @param userAge
 * @param ageFound
 * @return {boolean}
 */
export function isSameAge(userAge, ageFound) {
    // variance allows for +/- 1 on the data broker and +/- 1 based on the only having a birth year
    const ageVariance = 2;
    userAge = parseInt(userAge);
    ageFound = parseInt(ageFound);

    if (isNaN(ageFound)) {
        return false;
    }

    if (Math.abs(userAge - ageFound) < ageVariance) {
        return true;
    }

    return false;
}
