/**
 * Replaces placeholders in a given string with corresponding values from an object.
 *
 * @param {string|null|undefined} subject - The string to be modified.
 * @param {object} [replacements] - An object containing key-value pairs, where the key is the placeholder and the value is the replacement value.
 * @param {number} [textLength=1] - The desired length of the modified string. If specified, the string will be repeated to match the desired length.
 * @returns {string} - The modified string with placeholders replaced by corresponding values.
 */
export function apply(subject, replacements, textLength = 1) {
    // if no string is provided, just return an empty string (this will cover empty strings too)
    if (typeof subject !== 'string' || subject.length === 0) return '';

    let out = subject;

    // only replace `{...}` if the object is present
    if (replacements) {
        for (let [name, value] of Object.entries(replacements)) {
            if (typeof value !== 'string') value = '';
            out = out.replaceAll(`{${name}}`, value);
        }
    }

    // lengthen the string if textValue is not `1` (the default)
    if (textLength !== 1 && textLength > 0 && textLength <= 2) {
        const targetLen = Math.ceil(out.length * textLength);
        const target = Math.ceil(textLength);
        const combined = out.repeat(target);
        return combined.slice(0, targetLen);
    }

    return out;
}
