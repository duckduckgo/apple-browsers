/**
 * DarkReader content script
 *
 * Uses the DarkReader npm API to follow the system color scheme.
 * When the device is in dark mode, DarkReader automatically generates
 * a dark theme for the current web page.
 */
DarkReader.auto({
    brightness: 100,
    contrast: 100,
    sepia: 0
});
