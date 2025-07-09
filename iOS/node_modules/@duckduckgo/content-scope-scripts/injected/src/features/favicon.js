import ContentFeature from '../content-feature.js';
import { isBeingFramed } from '../utils.js';

export class Favicon extends ContentFeature {
    init() {
        if (this.platform.name === 'ios') return;

        /**
         * This feature never operates in a frame
         */
        if (isBeingFramed()) return;

        window.addEventListener('DOMContentLoaded', () => {
            // send once, immediately
            this.send();

            // then optionally watch for changes
            this.monitorChanges();
        });
    }

    monitorChanges() {
        // if there was an explicit opt-out, do nothing
        // this allows the remote config to be absent for this feature
        if (this.getFeatureSetting('monitor') === false) return;

        let trailing;
        let lastEmitTime = performance.now();
        const interval = 50;

        monitor(() => {
            clearTimeout(trailing);
            const currentTime = performance.now();
            const delta = currentTime - lastEmitTime;
            if (delta >= interval) {
                this.send();
            } else {
                trailing = setTimeout(() => {
                    this.send();
                }, 50);
            }
            lastEmitTime = currentTime;
        });
    }

    send() {
        const favicons = getFaviconList();
        this.notify('faviconFound', { favicons, documentUrl: document.URL });
    }
}

export default Favicon;

/**
 * @param {()=>void} changeObservedCallback
 */
function monitor(changeObservedCallback) {
    const target = document.head;
    if (!target) return;

    const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
            if (mutation.type === 'attributes' && mutation.target instanceof HTMLLinkElement) {
                changeObservedCallback();
                return;
            }
            if (mutation.type === 'childList') {
                for (const addedNode of mutation.addedNodes) {
                    if (addedNode instanceof HTMLLinkElement) {
                        changeObservedCallback();
                        return;
                    }
                }
                for (const removedNode of mutation.removedNodes) {
                    if (removedNode instanceof HTMLLinkElement) {
                        changeObservedCallback();
                        return;
                    }
                }
            }
        }
    });

    observer.observe(target, { attributeFilter: ['rel', 'href'], attributes: true, subtree: true, childList: true });
}

/**
 * @returns {import('../types/favicon.js').FaviconAttrs[]}
 */
function getFaviconList() {
    const selectors = [
        "link[href][rel='favicon']",
        "link[href][rel*='icon']",
        "link[href][rel='apple-touch-icon']",
        "link[href][rel='apple-touch-icon-precomposed']",
    ];
    const elements = document.head.querySelectorAll(selectors.join(','));
    return Array.from(elements).map((/** @type {HTMLLinkElement} */ link) => {
        const href = link.href || '';
        const rel = link.getAttribute('rel') || '';
        return { href, rel };
    });
}
