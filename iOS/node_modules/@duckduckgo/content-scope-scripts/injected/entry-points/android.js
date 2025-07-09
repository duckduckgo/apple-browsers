/**
 * @module Android integration
 */
import { load, init } from '../src/content-scope-features.js';
import { processConfig } from './../src/utils';
import { AndroidMessagingConfig } from '../../messaging/index.js';

function initCode() {
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const config = $CONTENT_SCOPE$;
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const userUnprotectedDomains = $USER_UNPROTECTED_DOMAINS$;
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const userPreferences = $USER_PREFERENCES$;

    const processedConfig = processConfig(config, userUnprotectedDomains, userPreferences);

    const configConstruct = processedConfig;
    const messageCallback = configConstruct.messageCallback;
    const messageSecret = configConstruct.messageSecret;
    const javascriptInterface = configConstruct.javascriptInterface;
    processedConfig.messagingConfig = new AndroidMessagingConfig({
        messageSecret,
        messageCallback,
        javascriptInterface,
        target: globalThis,
        debug: processedConfig.debug,
    });

    load({
        platform: processedConfig.platform,
        site: processedConfig.site,
        bundledConfig: processedConfig.bundledConfig,
        messagingConfig: processedConfig.messagingConfig,
        messageSecret: processedConfig.messageSecret,
    });

    init(processedConfig);
}

initCode();
