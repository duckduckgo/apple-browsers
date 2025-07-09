import { BrokerProtectionPage } from '../page-objects/broker-protection.js';
/**
 * @import {PlaywrightTestArgs, PlaywrightTestOptions, PlaywrightWorkerArgs, PlaywrightWorkerOptions, TestType} from "@playwright/test"
 */

/**
 * @param {typeof import("@playwright/test").test} test
 * @return {TestType<PlaywrightTestArgs & PlaywrightTestOptions & PlaywrightWorkerArgs & PlaywrightWorkerOptions & { createConfiguredDbp: (config: Record<string, any>) => Promise<BrokerProtectionPage> }, {}>}
 */
export function createConfiguredDbpTest(test) {
    return test.extend({
        createConfiguredDbp: async ({ page }, use, workerInfo) => {
            /**
             * @param {Record<string, any>} config
             */
            const createWithConfig = async (config) => {
                const dbp = BrokerProtectionPage.create(page, workerInfo.project.use);
                await dbp.withFeatureConfig(config);
                return dbp;
            };

            await use(createWithConfig);
        },
    });
}

/**
 * @param {typeof import("@playwright/test").test} test
 * @return {TestType<PlaywrightTestArgs & PlaywrightTestOptions & PlaywrightWorkerArgs & PlaywrightWorkerOptions & { createConfiguredDbp: (config: Record<string, any>) => Promise<BrokerProtectionPage> }, {}>}
 */
export function createConfiguredDbpTestWithNavigation(test) {
    return test.extend({
        createConfiguredDbp: async ({ page }, use, workerInfo) => {
            /**
             * @param {object} params
             * @param {string} params.targetPage
             * @param {string|object} params.action
             * @param {Record<string, any>} params.config
             */
            const createWithConfig = async (params) => {
                const { config, targetPage, action } = params;
                const dbp = BrokerProtectionPage.create(page, workerInfo.project.use);
                await dbp.withFeatureConfig(config);
                await dbp.navigatesTo(targetPage);
                if (typeof action === 'string') {
                    dbp.receivesAction(action);
                } else {
                    await dbp.receivesInlineAction(action);
                }
                return dbp;
            };

            await use(createWithConfig);
        },
    });
}
