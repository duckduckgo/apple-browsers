/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */

import { createYoutubeURLForError } from '../../src/utils.js';

/**
 * @implements IframeFeature
 */
export class ClickCapture {
    /**
     * @param {object} params
     * @param {string} params.baseUrl
     */
    constructor({ baseUrl }) {
        this.baseUrl = baseUrl;
    }

    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        const handler = (e) => {
            if (!e.target) return;
            const target = /** @type {Element} */ (e.target);

            // only act on elements with a `href` property
            if (!('href' in target) || typeof target.href !== 'string') return;

            // try to convert the clicked link into something we can open on Youtube
            const next = createYoutubeURLForError(target.href, this.baseUrl);
            if (!next) return;

            e.preventDefault();
            e.stopImmediatePropagation();

            // if we get this far, we want to prevent the new tab from opening and just redirect within the same tab
            window.location.href = next;
        };

        iframe.contentDocument?.addEventListener('click', handler);

        return () => {
            iframe.contentDocument?.removeEventListener('click', handler);
        };
    }
}
