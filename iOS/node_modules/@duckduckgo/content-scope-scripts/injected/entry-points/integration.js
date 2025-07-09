import { load, init } from '../src/content-scope-features.js';
import { TestTransportConfig } from '../../messaging/index.js';
function getTopLevelURL() {
    try {
        // FROM: https://stackoverflow.com/a/7739035/73479
        // FIX: Better capturing of top level URL so that trackers in embedded documents are not considered first party
        if (window.location !== window.parent.location) {
            return new URL(window.location.href !== 'about:blank' ? document.referrer : window.parent.location.href);
        } else {
            return new URL(window.location.href);
        }
    } catch (error) {
        return new URL(location.href);
    }
}

function generateConfig() {
    const topLevelUrl = getTopLevelURL();
    return {
        debug: false,
        sessionKey: 'randomVal',
        platform: {
            name: 'extension',
        },
        currentCohorts: [
            {
                feature: 'contentScopeExperiments',
                subfeature: 'bloops',
                cohort: 'control',
            },
            {
                feature: 'contentScopeExperiments',
                subfeature: 'test',
                cohort: 'treatment',
            },
        ],
        site: {
            domain: topLevelUrl.hostname,
            url: topLevelUrl.href,
            isBroken: false,
            allowlisted: false,
            enabledFeatures: [
                'fingerprintingCanvas',
                'fingerprintingScreenSize',
                'navigatorInterface',
                'cookie',
                'webCompat',
                'apiManipulation',
                'duckPlayer',
                'duckPlayerNative',
            ],
        },
    };
}

/**
 * Simple object check.
 * @param item
 * @returns {boolean}
 */
function isObject(item) {
    return item && typeof item === 'object' && !Array.isArray(item);
}

/**
 * Deep merge two objects.
 * @param target
 * @param sources
 */
function mergeDeep(target, ...sources) {
    if (!sources.length) return target;
    const source = sources.shift();

    if (isObject(target) && isObject(source)) {
        for (const key in source) {
            if (isObject(source[key])) {
                if (!target[key]) Object.assign(target, { [key]: {} });
                mergeDeep(target[key], source[key]);
            } else {
                Object.assign(target, { [key]: source[key] });
            }
        }
    }

    return mergeDeep(target, ...sources);
}

async function initCode() {
    const topLevelUrl = getTopLevelURL();
    const processedConfig = generateConfig();

    // mock Messaging and allow for tests to intercept them
    globalThis.cssMessaging = processedConfig.messagingConfig = new TestTransportConfig({
        notify() {
            // noop
        },
        request: async () => {
            // noop
        },
        subscribe() {
            return () => {
                // noop
            };
        },
    });

    load({
        // @ts-expect-error Types of property 'name' are incompatible.
        platform: processedConfig.platform,
        site: processedConfig.site,
        bundledConfig: processedConfig.bundledConfig,
        messagingConfig: processedConfig.messagingConfig,
        currentCohorts: processedConfig.currentCohorts,
    });

    // mark this phase as loaded
    setStatus('loaded');

    if (!topLevelUrl.searchParams.has('wait-for-init-args')) {
        await init(processedConfig);
        setStatus('initialized');
        return;
    }

    // Wait for a message containing additional config
    document.addEventListener(
        'content-scope-init-args',
        async (evt) => {
            // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
            const merged = mergeDeep(processedConfig, evt.detail);
            // init features
            await init(merged);

            // set status to initialized so that tests can resume
            setStatus('initialized');
        },
        { once: true },
    );
}

/**
 * @param {"loaded" | "initialized"} status
 */
function setStatus(status) {
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    window.__content_scope_status = status;
}

initCode();
