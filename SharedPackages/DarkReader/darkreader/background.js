/**
 * Minimal background service worker for DarkReader.
 *
 * The DarkReader API handles all functionality within the content script.
 * This service worker exists to satisfy the MV3 manifest requirement and
 * to silently receive messages from the DarkReader API's internal chrome.runtime
 * messaging (which would otherwise produce "Receiving end does not exist" errors).
 */
chrome.runtime.onMessage.addListener(() => {});
