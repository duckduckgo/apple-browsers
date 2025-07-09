const DEFAULT_SIGN_IN_REQURED_HREF = '[href*="//support.google.com/youtube/answer/3037019"]';

export class Settings {
    /**
     * @param {object} params
     * @param {{name: ImportMeta['platform']}} [params.platform]
     * @param {{state: 'enabled' | 'disabled'}} [params.pip]
     * @param {{state: 'enabled' | 'disabled'}} [params.autoplay]
     * @param {{state: 'enabled' | 'disabled'}} [params.focusMode]
     * @param {import("../types/duckplayer.js").DuckPlayerPageSettings['customError']} [params.customError]
     */
    constructor({
        platform = { name: 'macos' },
        pip = { state: 'disabled' },
        autoplay = { state: 'enabled' },
        focusMode = { state: 'enabled' },
        customError = { state: 'disabled', settings: {}, signInRequiredSelector: '' },
    }) {
        this.platform = platform;
        this.pip = pip;
        this.autoplay = autoplay;
        this.focusMode = focusMode;
        this.customError = this.parseLegacyCustomError(customError);
    }

    /**
     * Parses custom error settings so that both old and new schemas are accepted.
     *
     * Old schema:
     * {
     *   state: "enabled",
     *   signInRequiredSelector: "div"
     * }
     *
     * New schema:
     * {
     *   state: "disabled",
     *   settings: {
     *     signInRequiredSelector: "div"
     *   }
     * }
     *
     * @param {import("../types/duckplayer.js").DuckPlayerPageSettings['customError']} initialSettings
     * @return {import("../types/duckplayer.js").CustomErrorSettings}
     */
    parseLegacyCustomError(initialSettings) {
        if (initialSettings?.state !== 'enabled') {
            return { state: 'disabled' };
        }

        const { settings, signInRequiredSelector } = initialSettings;

        return {
            state: 'enabled',
            settings: {
                ...settings,
                ...(signInRequiredSelector && { signInRequiredSelector }),
            },
        };
    }

    /**
     * @param {keyof import("../types/duckplayer.js").DuckPlayerPageSettings} named
     * @param {{state: 'enabled' | 'disabled'} | null | undefined} settings
     * @return {Settings}
     */
    withFeatureState(named, settings) {
        if (!settings) return this;
        /** @type {(keyof import("../types/duckplayer.js").DuckPlayerPageSettings)[]} */
        const valid = ['pip', 'autoplay', 'focusMode', 'customError'];
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

    /**
     * @param {string|null|undefined} newState
     * @return {Settings}
     */
    withDisabledFocusMode(newState) {
        if (newState === 'disabled' || newState === 'enabled') {
            return new Settings({
                ...this,
                focusMode: { state: newState },
            });
        }

        return this;
    }

    /**
     * @param {string|null|undefined} newState
     * @return {Settings}
     */
    withCustomError(newState) {
        if (newState === 'disabled') {
            return new Settings({
                ...this,
                customError: { state: 'disabled' },
            });
        }

        if (newState === 'enabled') {
            return new Settings({
                ...this,
                customError: {
                    state: 'enabled',
                    signOnRequiredSelector: DEFAULT_SIGN_IN_REQURED_HREF,
                },
            });
        }

        return this;
    }

    /**
     * @return {string}
     */
    get youtubeBase() {
        switch (this.platform.name) {
            case 'windows':
            case 'ios':
            case 'android': {
                return 'duck://player/openInYoutube';
            }
            case 'macos': {
                return 'https://www.youtube.com/watch';
            }
            default:
                throw new Error('unreachable');
        }
    }

    /**
     * @return {'desktop' | 'mobile'}
     */
    get layout() {
        switch (this.platform.name) {
            case 'windows':
            case 'macos': {
                return 'desktop';
            }
            case 'ios':
            case 'android': {
                return 'mobile';
            }
            default:
                return 'desktop';
        }
    }
}
