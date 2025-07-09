import { immutableJSONPatch } from 'immutable-json-patch';
import {
    camelcase,
    computeEnabledFeatures,
    matchHostname,
    parseFeatureSettings,
    computeLimitedSiteObject,
    isSupportedVersion,
} from './utils.js';
import { URLPattern } from 'urlpattern-polyfill';

/**
 * This class is extended by each feature to implement remote config handling:
 * - Parsing the remote config, with conditional logic applied,
 * - Providing API for features to check if they are enabled,
 * - Providing API for features to get their config.
 * - For external scripts, it provides API to update the site object for the feature, e.g when the URL has changed.
 */
export default class ConfigFeature {
    /** @type {import('./utils.js').RemoteConfig | undefined} */
    #bundledConfig;

    /** @type {string} */
    name;

    /**
     * @type {{
     *   debug?: boolean,
     *   platform: import('./utils.js').Platform,
     *   desktopModeEnabled?: boolean,
     *   forcedZoomEnabled?: boolean,
     *   featureSettings?: Record<string, unknown>,
     *   assets?: import('./content-feature.js').AssetConfig | undefined,
     *   site: import('./content-feature.js').Site,
     *   messagingConfig?: import('@duckduckgo/messaging').MessagingConfig,
     *   currentCohorts?: [{feature: string, cohort: string, subfeature: string}],
     * } | null}
     */
    #args;

    /**
     * @param {string} name
     * @param {import('./content-scope-features.js').LoadArgs} args
     */
    constructor(name, args) {
        this.name = name;
        const { bundledConfig, site, platform } = args;
        this.#bundledConfig = bundledConfig;
        this.#args = args;

        // If we have a bundled config, treat it as a regular config
        // This will be overriden by the remote config if it is available
        if (this.#bundledConfig && this.#args) {
            const enabledFeatures = computeEnabledFeatures(bundledConfig, site.domain, platform.version);
            this.#args.featureSettings = parseFeatureSettings(bundledConfig, enabledFeatures);
        }
    }

    /**
     * Call this when the top URL has changed, to recompute the site object.
     * This is used to update the path matching for urlPattern.
     */
    recomputeSiteObject() {
        if (this.#args) {
            this.#args.site = computeLimitedSiteObject();
        }
    }

    get args() {
        return this.#args;
    }

    set args(args) {
        this.#args = args;
    }

    get featureSettings() {
        return this.#args?.featureSettings;
    }

    /**
     * Given a config key, interpret the value as a list of conditionals objects, and return the elements that match the current page
     * Consider in your feature using patchSettings instead as per `getFeatureSetting`.
     * @param {string} featureKeyName
     * @return {any[]}
     * @protected
     */
    matchConditionalFeatureSetting(featureKeyName) {
        const conditionalChanges = this._getFeatureSettings()?.[featureKeyName] || [];
        return conditionalChanges.filter((rule) => {
            let condition = rule.condition;
            // Support shorthand for domain matching for backwards compatibility
            if (condition === undefined && 'domain' in rule) {
                condition = this._domainToConditonBlocks(rule.domain);
            }
            return this._matchConditionalBlockOrArray(condition);
        });
    }

    /**
     * Takes a list of domains and returns a list of condition blocks
     * @param {string|string[]} domain
     * @returns {ConditionBlock[]}
     */
    _domainToConditonBlocks(domain) {
        if (Array.isArray(domain)) {
            return domain.map((domain) => ({ domain }));
        } else {
            return [{ domain }];
        }
    }

    /**
     * Used to match conditional changes for a settings feature.
     * @typedef {object} ConditionBlock
     * @property {string[] | string} [domain]
     * @property {object} [urlPattern]
     * @property {object} [minSupportedVersion]
     * @property {object} [experiment]
     * @property {string} [experiment.experimentName]
     * @property {string} [experiment.cohort]
     */

    /**
     * Takes multiple conditional blocks and returns true if any apply.
     * @param {ConditionBlock|ConditionBlock[]} conditionBlock
     * @returns {boolean}
     */
    _matchConditionalBlockOrArray(conditionBlock) {
        if (Array.isArray(conditionBlock)) {
            return conditionBlock.some((block) => this._matchConditionalBlock(block));
        }
        return this._matchConditionalBlock(conditionBlock);
    }

    /**
     * Takes a conditional block and returns true if it applies.
     * All conditions must be met to return true.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchConditionalBlock(conditionBlock) {
        // List of conditions that we support currently, these return truthy if the condition is met
        /** @type {Record<string, (conditionBlock: ConditionBlock) => boolean>} */
        const conditionChecks = {
            domain: this._matchDomainConditional,
            urlPattern: this._matchUrlPatternConditional,
            experiment: this._matchExperimentConditional,
            minSupportedVersion: this._matchMinSupportedVersion,
        };

        for (const key in conditionBlock) {
            /*
               Unsupported condition so fail for backwards compatibility
               If you wish to support older clients you should create an old condition block
               without the unsupported key also.
               Such as:
               [
                    {
                        condition: {
                                domain: 'example.com'
                        }
                    },
                    {
                        condition: {
                                domain: 'example.com',
                                newKey: 'value'
                        }
                    }
                ]
             */
            if (!conditionChecks[key]) {
                return false;
            } else if (!conditionChecks[key].call(this, conditionBlock)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Takes a condition block and returns true if the current experiment matches the experimentName and cohort.
     * Expects:
     * ```json
     * {
     *   "experiment": {
     *      "experimentName": "experimentName",
     *      "cohort": "cohort-name"
     *    }
     * }
     * ```
     * Where featureName "contentScopeExperiments" has a subfeature "experimentName" and cohort "cohort-name"
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchExperimentConditional(conditionBlock) {
        if (!conditionBlock.experiment) return false;
        const experiment = conditionBlock.experiment;
        if (!experiment.experimentName || !experiment.cohort) return false;
        const currentCohorts = this.args?.currentCohorts;
        if (!currentCohorts) return false;
        return currentCohorts.some((cohort) => {
            return (
                cohort.feature === 'contentScopeExperiments' &&
                cohort.subfeature === experiment.experimentName &&
                cohort.cohort === experiment.cohort
            );
        });
    }

    /**
     * Takes a condtion block and returns true if the current url matches the urlPattern.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchUrlPatternConditional(conditionBlock) {
        const url = this.args?.site.url;
        if (!url) return false;
        if (typeof conditionBlock.urlPattern === 'string') {
            // Use the current URL as the base for matching
            return new URLPattern(conditionBlock.urlPattern, url).test(url);
        }
        const pattern = new URLPattern(conditionBlock.urlPattern);
        return pattern.test(url);
    }

    /**
     * Takes a condition block and returns true if the current domain matches the domain.
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchDomainConditional(conditionBlock) {
        if (!conditionBlock.domain) return false;
        const domain = this.args?.site.domain;
        if (!domain) return false;
        if (Array.isArray(conditionBlock.domain)) {
            // Explicitly check for an empty array as matchHostname will return true a single item array that matches
            return false;
        }
        return matchHostname(domain, conditionBlock.domain);
    }

    /**
     * Takes a condition block and returns true if the platform version satisfies the `minSupportedFeature`
     * @param {ConditionBlock} conditionBlock
     * @returns {boolean}
     */
    _matchMinSupportedVersion(conditionBlock) {
        if (!conditionBlock.minSupportedVersion) return false;
        return isSupportedVersion(conditionBlock.minSupportedVersion, this.#args?.platform?.version);
    }

    /**
     * Return the settings object for a feature
     * @param {string} [featureName] - The name of the feature to get the settings for; defaults to the name of the feature
     * @returns {any}
     */
    _getFeatureSettings(featureName) {
        const camelFeatureName = featureName || camelcase(this.name);
        return this.featureSettings?.[camelFeatureName];
    }

    /**
     * For simple boolean settings, return true if the setting is 'enabled'
     * For objects, verify the 'state' field is 'enabled'.
     * This allows for future forwards compatibility with more complex settings if required.
     * For example:
     * ```json
     * {
     *    "toggle": "enabled"
     * }
     * ```
     * Could become later (without breaking changes):
     * ```json
     * {
     *   "toggle": {
     *       "state": "enabled",
     *       "someOtherKey": 1
     *   }
     * }
     * ```
     * This also supports domain overrides as per `getFeatureSetting`.
     * @param {string} featureKeyName
     * @param {string} [featureName]
     * @returns {boolean}
     */
    getFeatureSettingEnabled(featureKeyName, featureName) {
        const result = this.getFeatureSetting(featureKeyName, featureName);
        if (typeof result === 'object') {
            return result.state === 'enabled';
        }
        return result === 'enabled';
    }

    /**
     * Return a specific setting from the feature settings
     * If the "settings" key within the config has a "conditionalChanges" key, it will be used to override the settings.
     * This uses JSONPatch to apply the patches to settings before getting the setting value.
     * For example.com getFeatureSettings('val') will return 1:
     * ```json
     *  {
     *      "settings": {
     *         "conditionalChanges": [
     *             {
     *                "domain": "example.com",
     *                "patchSettings": [
     *                    { "op": "replace", "path": "/val", "value": 1 }
     *                ]
     *             }
     *         ]
     *      }
     *  }
     * ```
     * "domain" can either be a string or an array of strings.
     * Additionally we support urlPattern for more complex matching.
     * For example.com getFeatureSettings('val') will return 1:
     * ```json
     * {
     *    "settings": {
     *       "conditionalChanges": [
     *          {
     *            "condition": {
     *                "urlPattern": "https://example.com/*",
     *            },
     *            "patchSettings": [
     *                { "op": "replace", "path": "/val", "value": 1 }
     *            ]
     *          }
     *       ]
     *   }
     * }
     * ```
     * We also support multiple conditions:
     * ```json
     * {
     *    "settings": {
     *       "conditionalChanges": [
     *          {
     *            "condition": [
     *                {
     *                    "urlPattern": "https://example.com/*",
     *                },
     *                {
     *                    "urlPattern": "https://other.com/path/something",
     *                },
     *            ],
     *            "patchSettings": [
     *                { "op": "replace", "path": "/val", "value": 1 }
     *            ]
     *          }
     *       ]
     *   }
     * }
     * ```
     *
     * For boolean states you should consider using getFeatureSettingEnabled.
     * @param {string} featureKeyName
     * @param {string} [featureName]
     * @returns {any}
     */
    getFeatureSetting(featureKeyName, featureName) {
        let result = this._getFeatureSettings(featureName);
        if (featureKeyName in ['domains', 'conditionalChanges']) {
            throw new Error(`${featureKeyName} is a reserved feature setting key name`);
        }
        // We only support one of these keys at a time, where conditionalChanges takes precedence
        let conditionalMatches = [];
        // Presence check using result to avoid the [] default response
        if (result?.conditionalChanges) {
            conditionalMatches = this.matchConditionalFeatureSetting('conditionalChanges');
        } else {
            conditionalMatches = this.matchConditionalFeatureSetting('domains');
        }
        for (const match of conditionalMatches) {
            if (match.patchSettings === undefined) {
                continue;
            }
            try {
                result = immutableJSONPatch(result, match.patchSettings);
            } catch (e) {
                console.error('Error applying patch settings', e);
            }
        }
        return result?.[featureKeyName];
    }

    /**
     * @returns {import('./utils.js').RemoteConfig | undefined}
     **/
    get bundledConfig() {
        return this.#bundledConfig;
    }
}
