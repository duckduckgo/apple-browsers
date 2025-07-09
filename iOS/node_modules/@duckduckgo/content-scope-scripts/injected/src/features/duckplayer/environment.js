import strings from '../../../../build/locales/duckplayer-locales.js';

export class Environment {
    allowedProxyOrigins = ['duckduckgo.com'];
    _strings = JSON.parse(strings);

    /**
     * @param {object} params
     * @param {{name: string}} params.platform
     * @param {boolean|null|undefined} [params.debug]
     * @param {ImportMeta['injectName']} params.injectName
     * @param {string} params.locale
     */
    constructor(params) {
        this.debug = Boolean(params.debug);
        this.injectName = params.injectName;
        this.platform = params.platform;
        this.locale = params.locale;
    }

    /**
     * @param {"overlays.json" | "native.json"} named
     * @returns {Record<string, string>}
     */
    strings(named) {
        const matched = this._strings[this.locale];
        if (matched) return matched[named];
        return this._strings.en[named];
    }

    /**
     * This is the URL of the page that the user is currently on
     * It's abstracted so that we can mock it in tests
     * @return {string}
     */
    getPlayerPageHref() {
        if (this.debug) {
            const url = new URL(window.location.href);
            if (url.hostname === 'www.youtube.com') return window.location.href;

            // reflect certain query params, this is useful for testing
            if (url.searchParams.has('v')) {
                const base = new URL('/watch', 'https://youtube.com');
                base.searchParams.set('v', url.searchParams.get('v') || '');
                return base.toString();
            }

            return 'https://youtube.com/watch?v=123';
        }
        return window.location.href;
    }

    getLargeThumbnailSrc(videoId) {
        const url = new URL(`/vi/${videoId}/maxresdefault.jpg`, 'https://i.ytimg.com');
        return url.href;
    }

    setHref(href) {
        window.location.href = href;
    }

    hasOneTimeOverride() {
        try {
            // #ddg-play is a hard requirement, regardless of referrer
            if (window.location.hash !== '#ddg-play') return false;

            // double-check that we have something that might be a parseable URL
            if (typeof document.referrer !== 'string') return false;
            if (document.referrer.length === 0) return false; // can be empty!

            const { hostname } = new URL(document.referrer);
            const isAllowed = this.allowedProxyOrigins.includes(hostname);
            return isAllowed;
        } catch (e) {
            console.error(e);
        }
        return false;
    }

    isIntegrationMode() {
        return this.debug === true && this.injectName === 'integration';
    }

    isTestMode() {
        return this.debug === true;
    }

    get opensVideoOverlayLinksViaMessage() {
        return this.platform.name !== 'windows';
    }

    /**
     * @return {boolean}
     */
    get isMobile() {
        return this.platform.name === 'ios' || this.platform.name === 'android';
    }

    /**
     * @return {boolean}
     */
    get isDesktop() {
        return !this.isMobile;
    }

    /**
     * @return {'desktop' | 'mobile'}
     */
    get layout() {
        if (this.platform.name === 'ios' || this.platform.name === 'android') {
            return 'mobile';
        }
        return 'desktop';
    }
}
