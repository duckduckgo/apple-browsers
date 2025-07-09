/**
 * Execs a string.replace and ensures the searchRegex is found
 * @param {string} string
 * @param {RegExp} searchRegex - Use groupings for more complex operations
 * @param {string} replace
 * @returns {string}
 * @throws {Error} - If the string does not contain the searchRegex
 */
function replaceInString(string, searchRegex, replace) {
    if (!searchRegex.test(string)) {
        const errorMsg = 'No match found in the string. Check both string and regex.';
        console.log(errorMsg);
        console.log(string);
        throw new Error(errorMsg);
    }
    return string.replaceAll(new RegExp(searchRegex.source, 'gi'), replace);
}

/**
 * Execs multiple string.replace and ensures the searchRegexes are found
 * @param {string} string
 * @param {[searchRegex: RegExp, replace?: string][]} changes
 * @returns {string}
 * @throws {Error} - If the string does not contain the searchRegex
 */
function replaceAllInString(string, changes) {
    let updatedFile = string;
    for (const [searchRegex, replace = ''] of changes) {
        updatedFile = replaceInString(updatedFile, searchRegex, replace);
    }
    return updatedFile;
}

/**
 * Creates an html <a> tag from a url and an optional anchor text
 * @param {string} url
 * @param {string} [anchor]
 * @returns {string}
 */
function getLink(url, anchor) {
    return `<a href="${url}">${anchor || url}</a>`;
}

/**
 * Wraps the passed content string within a <li></li>
 * @param {string} content
 * @returns {string}
 */
function wrapInLi(content) {
    return `<li>${content}</li>`;
}

module.exports = {
    replaceInString,
    replaceAllInString,
    getLink,
    wrapInLi,
};
