/**
 * @module Apple integration
 */
import { load, init } from '../src/content-scope-features.js';
import { processConfig, platformSpecificFeatures } from './../src/utils';
import { WebkitMessagingConfig } from '../../messaging/index.js';

function initCode() {
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const config = $CONTENT_SCOPE$;
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const userUnprotectedDomains = $USER_UNPROTECTED_DOMAINS$;
    // @ts-expect-error https://app.asana.com/0/1201614831475344/1203979574128023/f
    const userPreferences = $USER_PREFERENCES$;

    const processedConfig = processConfig(config, userUnprotectedDomains, userPreferences, platformSpecificFeatures);

    const handlerNames = [];
    if (import.meta.injectName === 'apple-isolated') {
        handlerNames.push('contentScopeScriptsIsolated');
    } else {
        handlerNames.push('contentScopeScripts');
    }
    processedConfig.messagingConfig = new WebkitMessagingConfig({
        webkitMessageHandlerNames: handlerNames,
        secret: '',
        hasModernWebkitAPI: true,
    });

    load({
        platform: processedConfig.platform,
        site: processedConfig.site,
        bundledConfig: processedConfig.bundledConfig,
        messagingConfig: processedConfig.messagingConfig,
        messageSecret: processedConfig.messageSecret,
    });

    init(processedConfig);

    // Not supported:
    // update(message)
}

initCode();
