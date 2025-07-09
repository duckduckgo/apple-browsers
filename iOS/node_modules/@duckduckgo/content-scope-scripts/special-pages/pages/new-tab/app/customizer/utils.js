/**
 * Determines if a light or dark theme should be used based on background color
 * @param {string} backgroundColor - HEX color code (6 or 8 digits)
 * @returns {'light' | 'dark'} - Returns 'light' or 'dark'
 */
export function detectThemeFromHex(backgroundColor) {
    // Remove # if present and handle both 6 and 8 digit hex codes
    const hex = backgroundColor.replace('#', '');

    // Extract RGB values
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);

    // Calculate relative luminance using sRGB coefficients
    // Using the formula from WCAG 2.0
    const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;

    // Choose theme based on luminance
    // 128 is the middle value (255/2)
    return luminance < 128 ? 'dark' : 'light';
}

/**
 * This will apply default background colors as early as possible.
 *
 * @param {import("../../types/new-tab.ts").DefaultStyles | null | undefined} defaultStyles
 */
export function applyDefaultStyles(defaultStyles) {
    if (defaultStyles?.lightBackgroundColor) {
        document.body.style.setProperty('--default-light-background-color', defaultStyles.lightBackgroundColor);
    }
    if (defaultStyles?.darkBackgroundColor) {
        document.body.style.setProperty('--default-dark-background-color', defaultStyles.darkBackgroundColor);
    }
}
