export class Settings {
    /**
     * @param {object} params
     * @param {{name: 'macos' | 'windows'}} [params.platform]
     * @param {{state: 'enabled' | 'disabled', autoOpen: boolean}} [params.customizerDrawer]
     * @param {{state: 'enabled' | 'disabled'}} [params.adBlocking]
     */
    constructor({
        platform = { name: 'macos' },
        customizerDrawer = { state: 'enabled', autoOpen: false },
        adBlocking = { state: 'disabled' },
    }) {
        this.platform = platform;
        this.customizerDrawer = customizerDrawer;
        this.adBlocking = adBlocking;
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
     * @param {keyof import("../types/new-tab.js").NewTabPageSettings} named
     * @param {{state: 'enabled' | 'disabled'} | null | undefined} settings
     * @return {Settings}
     */
    withFeatureState(named, settings) {
        if (!settings) return this;
        /** @type {(keyof import("../types/new-tab.js").NewTabPageSettings)[]} */
        const valid = ['customizerDrawer', 'adBlocking'];
        if (!valid.includes(named)) {
            console.warn(`Excluding invalid feature key ${named}`);
            return this;
        }

        if (settings.state === 'enabled' || settings.state === 'disabled') {
            return new Settings({
                ...this,
                [named]: settings,
            });
        }
        return this;
    }

    get batchedActivityApi() {
        if (this.platform.name === 'windows') return { state: 'enabled' };
        return { state: 'disabled' };
    }
}
