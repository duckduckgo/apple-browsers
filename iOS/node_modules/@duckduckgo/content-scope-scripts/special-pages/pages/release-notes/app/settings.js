export class Settings {
    /**
     * @param {object} params
     * @param {{name: 'macos' | 'windows'}} [params.platform]
     */
    constructor({ platform = { name: 'macos' } }) {
        this.platform = platform;
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
}
