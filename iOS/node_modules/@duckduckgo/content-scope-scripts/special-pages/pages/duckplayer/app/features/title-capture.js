/**
 * @typedef {import("./iframe").IframeFeature} IframeFeature
 */
import { getValidVideoTitle } from '../../src/utils.js';

/**
 * @implements IframeFeature
 */
export class TitleCapture {
    /**
     * @param {HTMLIFrameElement} iframe
     */
    iframeDidLoad(iframe) {
        /** @type {(title: string) => void} */
        const setter = (title) => {
            const validTitle = getValidVideoTitle(title);
            if (validTitle) {
                document.title = 'Duck Player - ' + validTitle;
            }
        };

        const doc = iframe.contentDocument;
        const win = iframe.contentWindow;

        if (!doc) {
            console.log('could not access contentDocument');
            return () => {};
        }

        if (doc.title) {
            setter(doc.title);
        }
        if (win && doc) {
            const titleElem = doc.querySelector('title');

            if (titleElem) {
                // @ts-expect-error - typescript known about MutationObserver in this context
                const observer = new win.MutationObserver(function (mutations) {
                    mutations.forEach(function (mutation) {
                        setter(mutation.target.textContent);
                    });
                });
                observer.observe(titleElem, { childList: true });
            } else {
                console.warn('could not access title in iframe');
            }
        } else {
            console.warn('could not access iframe?.contentWindow && iframe?.contentDocument');
        }

        return null;
    }
}
