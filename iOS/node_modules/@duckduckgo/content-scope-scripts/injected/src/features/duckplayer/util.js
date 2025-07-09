/* eslint-disable promise/prefer-await-to-then */

/**
 * Try to load an image first. If the status code is 2xx, then continue
 * to load
 * @param {HTMLElement} parent
 * @param {string} targetSelector
 * @param {string} imageUrl
 */
export function appendImageAsBackground(parent, targetSelector, imageUrl) {
    const canceled = false;

    /**
     * Make a HEAD request to see what the status of this image is, without
     * having to fully download it.
     *
     * This is needed because YouTube returns a 404 + valid image file when there's no
     * thumbnail and you can't tell the difference through the 'onload' event alone
     */
    fetch(imageUrl, { method: 'HEAD' })
        .then((x) => {
            const status = String(x.status);
            if (canceled) return console.warn('not adding image, cancelled');
            if (status.startsWith('2')) {
                if (!canceled) {
                    append();
                } else {
                    console.warn('ignoring cancelled load');
                }
            } else {
                markError();
            }
        })
        .catch(() => {
            console.error('e from fetch');
        });

    /**
     * If loading fails, mark the parent with data-attributes
     */
    function markError() {
        parent.dataset.thumbLoaded = String(false);
        parent.dataset.error = String(true);
    }

    /**
     * If loading succeeds, try to append the image
     */
    function append() {
        const targetElement = parent.querySelector(targetSelector);
        if (!(targetElement instanceof HTMLElement)) {
            return console.warn('could not find child with selector', targetSelector, 'from', parent);
        }
        parent.dataset.thumbLoaded = String(true);
        parent.dataset.thumbSrc = imageUrl;
        const img = new Image();
        img.src = imageUrl;
        img.onload = function () {
            if (canceled) return console.warn('not adding image, cancelled');
            targetElement.style.backgroundImage = `url(${imageUrl})`;
            targetElement.style.backgroundSize = 'cover';
        };
        img.onerror = function () {
            if (canceled) return console.warn('not calling markError, cancelled');
            markError();
            const targetElement = parent.querySelector(targetSelector);
            if (!(targetElement instanceof HTMLElement)) return;
            targetElement.style.backgroundImage = '';
        };
    }
}

export class SideEffects {
    /**
     * @param {object} params
     * @param {boolean} [params.debug]
     */
    constructor({ debug = false } = {}) {
        this.debug = debug;
    }

    /** @type {{fn: () => void, name: string}[]} */
    _cleanups = [];
    /**
     * Wrap a side-effecting operation for easier debugging
     * and teardown/release of resources
     * @param {string} name
     * @param {() => () => void} fn
     */
    add(name, fn) {
        try {
            if (this.debug) {
                console.log('☢️', name);
            }
            const cleanup = fn();
            if (typeof cleanup === 'function') {
                this._cleanups.push({ name, fn: cleanup });
            }
        } catch (e) {
            console.error('%s threw an error', name, e);
        }
    }

    /**
     * Remove elements, event listeners etc
     * @param {string} [name]
     */
    destroy(name) {
        const cleanups = name ? this._cleanups.filter((c) => c.name === name) : this._cleanups;
        for (const cleanup of cleanups) {
            if (typeof cleanup.fn === 'function') {
                try {
                    if (this.debug) {
                        console.log('🗑️', cleanup.name);
                    }
                    cleanup.fn();
                } catch (e) {
                    console.error(`cleanup ${cleanup.name} threw`, e);
                }
            } else {
                throw new Error('invalid cleanup');
            }
        }
        if (name) {
            this._cleanups = this._cleanups.filter((c) => c.name !== name);
        } else {
            this._cleanups = [];
        }
    }
}

/**
 * A container for valid/parsed video params.
 *
 * If you have an instance of `VideoParams`, then you can trust that it's valid, and you can always
 * produce a PrivatePlayer link from it
 *
 * The purpose is to co-locate all processing of search params/pathnames for easier security auditing/testing
 *
 * @example
 *
 * ```
 * const privateUrl = VideoParams.fromHref("https://example.com/foo/bar?v=123&t=21")?.toPrivatePlayerUrl()
 *       ^^^^ <- this is now null, or a string if it was valid
 * ```
 */
export class VideoParams {
    /**
     * @param {string} id - the YouTube video ID
     * @param {string|null|undefined} time - an optional time
     */
    constructor(id, time) {
        this.id = id;
        this.time = time;
    }

    static validVideoId = /^[a-zA-Z0-9-_]+$/;
    static validTimestamp = /^[0-9hms]+$/;

    /**
     * @returns {string}
     */
    toPrivatePlayerUrl() {
        // no try/catch because we already validated the ID
        // in Microsoft WebView2 v118+ changing from special protocol (https) to non-special one (duck) is forbidden
        // so we need to construct duck player this way
        const duckUrl = new URL(`duck://player/${this.id}`);

        if (this.time) {
            duckUrl.searchParams.set('t', this.time);
        }
        return duckUrl.href;
    }

    /**
     * Get the large thumbnail URL for the current video id
     *
     * @returns {string}
     */
    toLargeThumbnailUrl() {
        const url = new URL(`/vi/${this.id}/maxresdefault.jpg`, 'https://i.ytimg.com');
        return url.href;
    }

    /**
     * Create a VideoParams instance from a href, only if it's on the watch page
     *
     * @param {string} href
     * @returns {VideoParams|null}
     */
    static forWatchPage(href) {
        let url;
        try {
            url = new URL(href);
        } catch (e) {
            return null;
        }
        if (!url.pathname.startsWith('/watch')) {
            return null;
        }
        return VideoParams.fromHref(url.href);
    }

    /**
     * Convert a relative pathname into VideoParams
     *
     * @param pathname
     * @returns {VideoParams|null}
     */
    static fromPathname(pathname) {
        let url;
        try {
            url = new URL(pathname, window.location.origin);
        } catch (e) {
            return null;
        }
        return VideoParams.fromHref(url.href);
    }

    /**
     * Convert a href into valid video params. Those can then be converted into a private player
     * link when needed
     *
     * @param href
     * @returns {VideoParams|null}
     */
    static fromHref(href) {
        let url;
        try {
            url = new URL(href);
        } catch (e) {
            return null;
        }

        let id = null;

        // known params
        const vParam = url.searchParams.get('v');
        const tParam = url.searchParams.get('t');

        let time = null;

        // ensure youtube video id is good
        if (vParam && VideoParams.validVideoId.test(vParam)) {
            id = vParam;
        } else {
            // if the video ID is invalid, we cannot produce an instance of VideoParams
            return null;
        }

        // ensure timestamp is good, if set
        if (tParam && VideoParams.validTimestamp.test(tParam)) {
            time = tParam;
        }

        return new VideoParams(id, time);
    }
}

/**
 * A helper to run a callback when the DOM is loaded.
 * Construct this early, so that the event listener is added as soon as possible.
 * Then you can add callbacks to it, and they will be called when the DOM is loaded, or immediately
 * if the DOM is already loaded.
 */
export class DomState {
    loaded = false;
    loadedCallbacks = [];
    constructor() {
        window.addEventListener('DOMContentLoaded', () => {
            this.loaded = true;
            this.loadedCallbacks.forEach((cb) => cb());
        });
    }

    onLoaded(loadedCallback) {
        if (this.loaded) return loadedCallback();
        this.loadedCallbacks.push(loadedCallback);
    }
}

export class Logger {
    /** @type {string} */
    id;
    /** @type {() => boolean} */
    shouldLog;

    /**
     * @param {object} options
     * @param {string} options.id - Prefix added to log output
     * @param {() => boolean} options.shouldLog - Tells logger whether to output to console
     */
    constructor({ id, shouldLog }) {
        if (!id || !shouldLog) {
            throw new Error('Missing props in Logger');
        }
        this.shouldLog = shouldLog;
        this.id = id;
    }

    error(...args) {
        this.output(console.error, args);
    }

    info(...args) {
        this.output(console.info, args);
    }

    log(...args) {
        this.output(console.log, args);
    }

    warn(...args) {
        this.output(console.warn, args);
    }

    output(handler, args) {
        if (this.shouldLog()) {
            handler(`${this.id.padEnd(20, ' ')} |`, ...args);
        }
    }
}
