import { readFileSync } from 'node:fs';

/**
 * Allows per-platform values. The 'platform' string is powered from globals.d.ts
 * and it represents an artifact name.
 *
 * For example
 *
 * - windows
 * - apple
 * - apple-isolated
 *
 * @template {NonNullable<ImportMeta['platform']>} T
 * @template {() => any} VariantFn
 * @param {T} name
 * @param {Partial<Record<NonNullable<ImportMeta['platform']>, VariantFn>>} switchItems
 * @returns {ReturnType<VariantFn>}
 */
export function platform(name, switchItems) {
    if (name in switchItems) {
        const fn = switchItems[name];
        if (!fn) {
            throw new Error('missing impl for that');
        }
        return fn();
    }
    throw new Error('missing impl for that');
}

export class Build {
    /**
     * @param {NonNullable<ImportMeta['injectName']>} name
     */
    constructor(name) {
        this.name = name;
    }

    /**
     * @template {() => any} VariantFn
     * @param {Partial<Record<NonNullable<ImportMeta['injectName']>, VariantFn>>} switchItems
     * @returns {ReturnType<VariantFn>}
     */
    switch(switchItems) {
        if (this.name in switchItems) {
            const fn = switchItems[this.name];
            if (!fn) {
                throw new Error('missing impl for that');
            }
            return fn();
        }
        throw new Error('missing impl for that on platform: ' + this.name);
    }

    /**
     *
     * @returns string
     */
    get artifact() {
        const path = this.switch({
            windows: () => '../build/windows/contentScope.js',
            android: () => '../build/android/contentScope.js',
            apple: () => '../Sources/ContentScopeScripts/dist/contentScope.js',
            'apple-isolated': () => '../Sources/ContentScopeScripts/dist/contentScopeIsolated.js',
            'android-autofill-password-import': () => '../build/android/autofillPasswordImport.js',
            'android-broker-protection': () => '../build/android/brokerProtection.js',
        });
        return readFileSync(path, 'utf8');
    }

    /**
     * @param {any} name
     * @returns {ImportMeta['injectName']}
     */
    static supported(name) {
        /** @type {ImportMeta['injectName'][]} */
        const items = [
            'apple',
            'apple-isolated',
            'windows',
            'integration',
            'android',
            'android-autofill-password-import',
            'chrome-mv3',
            'firefox',
        ];
        if (items.includes(name)) {
            return name;
        }
        return undefined;
    }
}

export class PlatformInfo {
    /** @type {NonNullable<ImportMeta['platform']>} */
    name;
    /**
     * @param {object} params
     * @param {ImportMeta['platform']} params.name
     */
    constructor(params) {
        if (!params.name) throw new Error('unreachable - must provide .name');
        this.name = params.name;
    }

    /**
     * @param {any} name
     * @returns {ImportMeta['platform']}
     */
    static supported(name) {
        /** @type {ImportMeta['platform'][]} */
        const items = ['macos', 'ios', 'windows', 'android', 'extension'];
        if (items.includes(name)) {
            return name;
        }
        return undefined;
    }
}

/**
 * This takes the `use` part of the playwright config for each platform,
 * and then uses it to provide helpers to tests, such as looking up build artifacts.
 *
 * @param config
 * @returns {{build: Build; platformInfo: PlatformInfo}}
 */
export function perPlatform(config) {
    // Read the configuration object to determine which platform we're testing against
    if (!('injectName' in config) || typeof config.injectName !== 'string') {
        // Read the configuration object to determine which platform we're testing against
        throw new Error('unsupported project - missing `use.injectName`');
    }

    if (!('platform' in config) || typeof config.platform !== 'string') {
        throw new Error('unsupported project - missing `use.platform`');
    }

    const name = Build.supported(config.injectName);
    if (name) {
        const build = new Build(name);
        const platform = PlatformInfo.supported(config.platform);
        if (platform) {
            const platformInfo = new PlatformInfo({ name: platform });
            return { build, platformInfo };
        }
    }

    // If we get here, it's a mis-configuration
    throw new Error('unreachable');
}
