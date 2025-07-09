/**
 * The following code is originally from https://github.com/mozilla-extensions/secure-proxy/blob/db4d1b0e2bfe0abae416bf04241916f9e4768fd2/src/commons/template.js
 */
class Template {
    constructor(strings, values) {
        this.values = values;
        this.strings = strings;
    }

    /**
     * Escapes any occurrences of &, ", <, > or / with XML entities.
     *
     * @param {string} str
     *        The string to escape.
     * @return {string} The escaped string.
     */
    escapeXML(str) {
        const replacements = {
            '&': '&amp;',
            '"': '&quot;',
            "'": '&apos;',
            '<': '&lt;',
            '>': '&gt;',
            '/': '&#x2F;',
        };
        return String(str).replace(/[&"'<>/]/g, (m) => replacements[m]);
    }

    potentiallyEscape(value) {
        if (typeof value === 'object') {
            if (value instanceof Array) {
                return value.map((val) => this.potentiallyEscape(val)).join('');
            }

            // If we are an escaped template let join call toString on it
            if (value instanceof Template) {
                return value;
            }

            throw new Error('Unknown object to escape');
        }
        return this.escapeXML(value);
    }

    toString() {
        const result = [];

        for (const [i, string] of this.strings.entries()) {
            result.push(string);
            if (i < this.values.length) {
                result.push(this.potentiallyEscape(this.values[i]));
            }
        }
        return result.join('');
    }
}

export function html(strings, ...values) {
    return new Template(strings, values);
}

/**
 * @param {string} string
 * @return {Template}
 */
export function trustedUnsafe(string) {
    return html([string]);
}

/**
 * Use a policy if trustedTypes is available
 * @return {{createHTML: (s: string) => any}}
 */
export function createPolicy() {
    if (globalThis.trustedTypes) {
        return globalThis.trustedTypes?.createPolicy?.('ddg-default', { createHTML: (s) => s });
    }
    return {
        createHTML: (s) => s,
    };
}
