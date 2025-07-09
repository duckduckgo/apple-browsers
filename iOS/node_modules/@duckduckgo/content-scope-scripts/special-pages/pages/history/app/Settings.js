export class Settings {
    /**
     * @param {object} params
     * @param {{name: 'macos' | 'windows'}} [params.platform]
     * @param {number} [params.typingDebounce=100] how long to debounce typing in the search field - default: 100ms
     * @param {number} [params.urlDebounce=500] how long to debounce reflecting to the URL? - default: 500ms
     */
    constructor({ platform = { name: 'macos' }, typingDebounce = 100, urlDebounce = 500 }) {
        this.platform = platform;
        this.typingDebounce = typingDebounce;
        this.urlDebounce = urlDebounce;
    }

    withPlatformName(name) {
        /** @type {ImportMeta['platform'][]} */
        const valid = ['windows', 'macos'];
        if (valid.includes(/** @type {any} */ (name))) {
            return new Settings({
                ...this,
                platform: { name },
            });
        }
        return this;
    }

    /**
     * @param {null|undefined|number|string} value
     */
    withDebounce(value) {
        if (!value) return this;
        const input = String(value).trim();
        if (input.match(/^\d+$/)) {
            return new Settings({
                ...this,
                typingDebounce: parseInt(input, 10),
            });
        }
        return this;
    }

    /**
     * @param {null|undefined|number|string} value
     */
    withUrlDebounce(value) {
        if (!value) return this;
        const input = String(value).trim();
        if (input.match(/^\d+$/)) {
            return new Settings({
                ...this,
                urlDebounce: parseInt(input, 10),
            });
        }
        return this;
    }
}
