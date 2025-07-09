import { YOUTUBE_ERROR_EVENT, checkForError, getErrorType } from '../../../../../injected/src/features/duckplayer-native/youtube-errors.js';

/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 * @typedef {import('../../types/duckplayer').YouTubeError} YouTubeError
 * @typedef {import('../../types/duckplayer').CustomErrorSettings} CustomErrorSettings
 */

/**
 * Detects YouTube errors based on DOM queries
 *
 * @implements IframeFeature
 */
export class ErrorDetection {
    /** @type {HTMLIFrameElement} */
    iframe;

    /** @type {CustomErrorSettings} */
    options;

    /**
     * @param {CustomErrorSettings} options
     */
    constructor(options) {
        this.options = options;
        this.errorSelector = options?.settings?.youtubeErrorSelector || '.ytp-error';
        console.log('options', options);
    }

    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        this.iframe = iframe;

        if (this.options?.state !== 'enabled') {
            console.log('Error detection disabled');
            return null;
        }

        const contentWindow = iframe.contentWindow;
        const documentBody = contentWindow?.document?.body;
        if (contentWindow && documentBody) {
            // Check if iframe already contains error
            if (checkForError(this.errorSelector, documentBody)) {
                const error = getErrorType(contentWindow, this.options.settings?.signInRequiredSelector);
                window.dispatchEvent(new CustomEvent(YOUTUBE_ERROR_EVENT, { detail: { error } }));

                return null;
            }

            // Create a MutationObserver instance
            const observer = new MutationObserver(this.handleMutation.bind(this));

            // Start observing the iframe's document for changes
            observer.observe(documentBody, {
                childList: true,
                subtree: true, // Observe all descendants of the body
            });

            return () => {
                observer.disconnect();
            };
        }

        return null;
    }

    /**
     * Mutation handler that checks new nodes for error states
     *
     * @type {MutationCallback}
     */
    handleMutation(mutationsList) {
        for (const mutation of mutationsList) {
            if (mutation.type === 'childList') {
                mutation.addedNodes.forEach((node) => {
                    if (checkForError(this.errorSelector, node)) {
                        console.log('A node with an error has been added to the document:', node);
                        const error = getErrorType(this.iframe.contentWindow, this.options.settings?.signInRequiredSelector);

                        window.dispatchEvent(new CustomEvent(YOUTUBE_ERROR_EVENT, { detail: { error } }));
                    }
                });
            }
        }
    }
}
