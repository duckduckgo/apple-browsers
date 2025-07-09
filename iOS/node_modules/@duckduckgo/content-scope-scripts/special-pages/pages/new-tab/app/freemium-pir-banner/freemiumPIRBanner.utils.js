/**
 * @type {(markdown: string) => string} convertMarkdownToHTMLForStrongTags
 */

export function convertMarkdownToHTMLForStrongTags(markdown) {
    // first, remove any HTML tags
    markdown = escapeXML(markdown);

    // Use a regular expression to find all the words wrapped in **
    const regex = /\*\*(.*?)\*\*/g;

    // Replace the matched text with the HTML <strong> tags
    const result = markdown.replace(regex, '<strong>$1</strong>');
    return result;
}

/**
 * Escapes any occurrences of &, ", <, > or / with XML entities.
 */
function escapeXML(str) {
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
