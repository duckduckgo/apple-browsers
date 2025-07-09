import { Logger } from '../duckplayer/util.js';
import { checkForError, getErrorType } from './youtube-errors.js';

/**
 * @import {DuckPlayerNativeSettings} from "@duckduckgo/privacy-configuration/schema/features/duckplayer-native.js"
 * @typedef {"age-restricted" | "sign-in-required" | "no-embed" | "unknown"} YouTubeError
 * @typedef {DuckPlayerNativeSettings['selectors']} DuckPlayerNativeSelectors
 * @typedef {(error: YouTubeError) => void} ErrorDetectionCallback
 */

/**
 * @typedef {object} ErrorDetectionSettings
 * @property {DuckPlayerNativeSelectors} selectors
 * @property {ErrorDetectionCallback} callback
 * @property {boolean} testMode
 */

/**
 * Detects YouTube errors based on DOM queries
 */
export class ErrorDetection {
    /** @type {Logger} */
    logger;
    /** @type {DuckPlayerNativeSelectors} */
    selectors;
    /** @type {ErrorDetectionCallback} */
    callback;
    /** @type {boolean} */
    testMode;

    /**
     * @param {ErrorDetectionSettings} settings
     */
    constructor({ selectors, callback, testMode = false }) {
        if (!selectors?.youtubeError || !selectors?.signInRequiredError || !callback) {
            throw new Error('Missing selectors or callback props');
        }
        this.selectors = selectors;
        this.callback = callback;
        this.testMode = testMode;
        this.logger = new Logger({
            id: 'ERROR_DETECTION',
            shouldLog: () => this.testMode,
        });
    }

    /**
     *
     * @returns {(() => void)|void}
     */
    observe() {
        const documentBody = document?.body;
        if (documentBody) {
            // Check if iframe already contains error
            if (checkForError(this.selectors.youtubeError, documentBody)) {
                const error = getErrorType(window, this.selectors.signInRequiredError, this.logger);
                this.handleError(error);
                return;
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
    }

    /**
     *
     * @param {YouTubeError} errorId
     */
    handleError(errorId) {
        if (this.callback) {
            this.logger.log('Calling error handler for', errorId);
            this.callback(errorId);
        } else {
            this.logger.warn('No error callback found');
        }
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
                    if (checkForError(this.selectors.youtubeError, node)) {
                        this.logger.log('A node with an error has been added to the document:', node);
                        const error = getErrorType(window, this.selectors.signInRequiredError, this.logger);
                        this.handleError(error);
                    }
                });
            }
        }
    }
}
