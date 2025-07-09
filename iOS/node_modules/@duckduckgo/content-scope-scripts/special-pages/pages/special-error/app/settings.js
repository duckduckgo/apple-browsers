export class Settings {
    /**
     * @param {object} params
     * @param {{name: ImportMeta['platform']}} [params.platform]
     */
    constructor({ platform = { name: 'macos' } }) {
        this.platform = platform;
    }

    withPlatformName(name) {
        /** @type {ImportMeta['platform'][]} */
        const valid = ['windows', 'macos', 'ios', 'android'];
        if (valid.includes(/** @type {any} */ (name))) {
            return new Settings({
                ...this,
                platform: { name },
            });
        }
        return this;
    }
}
