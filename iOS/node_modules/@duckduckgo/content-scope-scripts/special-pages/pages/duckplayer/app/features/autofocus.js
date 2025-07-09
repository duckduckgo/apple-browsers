/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */

/**
 * @implements IframeFeature
 */
export class AutoFocus {
    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        const maxAttempts = 1000;
        let attempt = 0;
        let id;

        function check() {
            if (!iframe.contentDocument) return;
            if (attempt > maxAttempts) return;

            attempt += 1;

            const selector = '#player video';

            // try to select the video element
            const video = /** @type {HTMLIFrameElement | null} */ (iframe.contentDocument?.body.querySelector(selector));

            // if the video is absent, try again
            if (!video) {
                id = requestAnimationFrame(check);
                return;
            }

            // programmatically focus the video element
            video.focus();

            // in a dev/test environment only, append a signal to the outer document
            document.body.dataset.videoState = 'loaded+focussed';
        }

        id = requestAnimationFrame(check);

        return () => {
            cancelAnimationFrame(id);
        };
    }
}
