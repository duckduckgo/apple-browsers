/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */

import { VideoParams } from 'injected/src/features/duckplayer/util';

/**
 * @implements IframeFeature
 */
export class ReplaceWatchLinks {
    /**
     * @param {string} videoId
     * @param {() => void} handler - what to invoke when a watch-link was clicked
     */
    constructor(videoId, handler) {
        this.videoId = videoId;
        this.handler = handler;
    }
    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        const doc = iframe.contentDocument;
        const win = iframe.contentWindow;

        if (!doc) {
            console.log('could not access contentDocument');
            return () => {};
        }

        if (win && doc) {
            doc.addEventListener(
                'click',
                (e) => {
                    if (!(e.target instanceof /** @type {any} */ (win).Element)) return;

                    /** @type {HTMLLinkElement|null} */
                    const closestLink = /** @type {Element} */ (e.target).closest('a[href]');
                    if (closestLink && this.isWatchLink(closestLink.href)) {
                        e.preventDefault();
                        e.stopPropagation();
                        this.handler();
                    }
                },
                {
                    capture: true,
                },
            );
        } else {
            console.warn('could not access iframe?.contentWindow && iframe?.contentDocument');
        }

        return null;
    }

    /**
     * @param {string} href
     * @return {boolean}
     */
    isWatchLink(href) {
        const videoParams = VideoParams.forWatchPage(href);
        return videoParams?.id === this.videoId;
    }
}
