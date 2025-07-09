/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */

/**
 * Capture mousemove events inside the iframe and dispatch them
 * This allows things like focus-mode to listen to this event and decide whether to
 * pause or not.
 *
 * @implements IframeFeature
 */
export class MouseCapture {
    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        iframe.contentDocument?.addEventListener('mousemove', () => {
            window.dispatchEvent(new Event('iframe-mousemove'));
        });
        return null;
    }
}
