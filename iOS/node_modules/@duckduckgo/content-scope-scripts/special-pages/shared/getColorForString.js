const EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES = [
    '#94B3AF',
    '#727998',
    '#645468',
    '#4D5F7F',
    '#855DB6',
    '#5E5ADB',
    '#678FFF',
    '#6BB4EF',
    '#4A9BAE',
    '#66C4C6',
    '#55D388',
    '#99DB7A',
    '#ECCC7B',
    '#E7A538',
    '#DD6B4C',
    '#D65D62',
];

/**
 * Note: I used claude.ai to convert https://github.com/duckduckgo/macos-browser/blob/main/LocalPackages/SwiftUIExtensions/Sources/SwiftUIExtensions/ColorExtensions.swift#L40
 *  - Big Int is needed to correctly match the way it works in swift, so that migrating users
 *  see the same color background on fallback favicons
 *
 * @param {string} str
 * @param {bigint | number | string} arrayLength
 */
function getArrayIndex(str, arrayLength) {
    const utf8Encoder = new TextEncoder();
    const bytes = utf8Encoder.encode(str);

    let hash = BigInt(5381);

    // Directly match Swift's reduce operation
    for (const byte of bytes) {
        hash = (hash << BigInt(5)) + hash + BigInt(byte);
        hash = BigInt.asIntN(64, hash);
    }

    // Match Swift's modulo then abs operation
    const index = hash % BigInt(arrayLength);
    return Number(index < 0 ? -index : index);
}

// Add a simple cache mechanism to store previously calculated colors
const urlToColorCache = new Map();

/**
 * @param {string} url
 * @return {string|null}
 */
export function urlToColor(url) {
    if (typeof url !== 'string') return null;
    if (urlToColorCache.has(url)) {
        return urlToColorCache.get(url);
    }

    const index = getArrayIndex(url, EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES.length);
    const color = EMPTY_FAVICON_TEXT_BACKGROUND_COLOR_BRUSHES[index];

    urlToColorCache.set(url, color);
    return color;
}
