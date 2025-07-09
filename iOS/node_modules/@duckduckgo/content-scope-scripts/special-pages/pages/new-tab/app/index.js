import { render, h } from 'preact';
import { App, AppLevelErrorBoundaryFallback } from './components/App.js';
import { EnvironmentProvider, UpdateEnvironment } from '../../../shared/components/EnvironmentProvider.js';
import { SettingsProvider } from './settings.provider.js';
import { InitialSetupContext, MessagingContext, TelemetryContext } from './types';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider.js';
import { WidgetConfigService } from './widget-list/widget-config.service.js';
import enStrings from '../public/locales/en/new-tab.json';
import { WidgetConfigProvider } from './widget-list/widget-config.provider.js';
import { Settings } from './settings.js';
import { Components } from './components/Components.jsx';
import { widgetEntryPoint } from './widget-list/WidgetList.js';
import { callWithRetry } from '../../../shared/call-with-retry.js';
import { CustomizerProvider } from './customizer/CustomizerProvider.js';
import { CustomizerService } from './customizer/customizer.service.js';
import { InlineErrorBoundary } from './InlineErrorBoundary.js';
import { DocumentVisibilityProvider } from '../../../shared/components/DocumentVisibility.js';
import { applyDefaultStyles } from './customizer/utils.js';

/**
 * @import {Telemetry} from "./telemetry/telemetry.js"
 * @import { Environment } from "../../../shared/environment";
 * @param {Element} root
 * @param {import("../src/index.js").NewTabPage} messaging
 * @param {import("./telemetry/telemetry.js").Telemetry} telemetry
 * @param {Environment} baseEnvironment
 * @throws Error
 */
export async function init(root, messaging, telemetry, baseEnvironment) {
    const result = await callWithRetry(() => messaging.initialSetup());

    // handle fatal exceptions, the following things prevent anything from starting.
    if ('error' in result) {
        throw new Error(result.error);
    }

    const init = result.value;
    console.log('INITIAL DATA', init);

    if (!Array.isArray(init.widgets)) {
        throw new Error('missing critical initialSetup.widgets array');
    }
    if (!Array.isArray(init.widgetConfigs)) {
        throw new Error('missing critical initialSetup.widgetConfig array');
    }

    // update the 'env' in case it was changed by native sides
    const environment = baseEnvironment
        .withEnv(init.env)
        .withLocale(init.locale)
        .withLocale(baseEnvironment.urlParams.get('locale'))
        .withTextLength(baseEnvironment.urlParams.get('textLength'))
        .withDisplay(baseEnvironment.urlParams.get('display'));

    // read the translation file
    const strings = await getStrings(environment);

    // create app-specific settings
    const settings = new Settings({})
        .withPlatformName(baseEnvironment.injectName)
        .withPlatformName(init.platform?.name)
        .withPlatformName(baseEnvironment.urlParams.get('platform'))
        .withFeatureState('customizerDrawer', init.settings?.customizerDrawer)
        .withFeatureState('adBlocking', init.settings?.adBlocking);

    if (!window.__playwright_01) {
        console.log('environment:', environment);
        console.log('settings:', settings);
        console.log('locale:', environment.locale);
    }

    /**
     * @param {string} message
     */
    const didCatch = (message) => {
        messaging.reportPageException({ message });
    };

    // install global side effects that are not specific to any widget
    installGlobalSideEffects(environment, settings);

    // apply default styles
    applyDefaultStyles(init.customizer?.defaultStyles);

    // return early if we're in the 'components' view.
    if (environment.display === 'components') {
        return renderComponents(root, environment, settings, strings);
    }

    // Resolve the entry points for each selected widget
    const entryPoints = await resolveEntryPoints(init.widgets, didCatch);

    // Create an instance of the global widget api
    const widgetConfigAPI = new WidgetConfigService(messaging, init.widgetConfigs);

    /** @type {import('../types/new-tab.js').CustomizerData} */
    const customizerData = init.customizer || {
        userColor: null,
        background: { kind: 'default' },
        theme: 'system',
        userImages: [],
    };

    const customizerApi = new CustomizerService(messaging, customizerData);

    render(
        <EnvironmentProvider
            debugState={environment.debugState}
            injectName={environment.injectName}
            willThrow={environment.willThrow}
            env={environment.env}
            locale={environment.locale}
        >
            <InlineErrorBoundary
                context={'App entry point'}
                fallback={(message) => <AppLevelErrorBoundaryFallback>{message}</AppLevelErrorBoundaryFallback>}
            >
                <UpdateEnvironment search={window.location.search} />
                <MessagingContext.Provider value={messaging}>
                    <InitialSetupContext.Provider value={init}>
                        <TelemetryContext.Provider value={telemetry}>
                            <SettingsProvider settings={settings}>
                                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                                    <CustomizerProvider service={customizerApi} initialData={customizerData}>
                                        <DocumentVisibilityProvider>
                                            <WidgetConfigProvider
                                                api={widgetConfigAPI}
                                                widgetConfigs={init.widgetConfigs}
                                                widgets={init.widgets}
                                                entryPoints={entryPoints}
                                            >
                                                <App />
                                            </WidgetConfigProvider>
                                        </DocumentVisibilityProvider>
                                    </CustomizerProvider>
                                </TranslationProvider>
                            </SettingsProvider>
                        </TelemetryContext.Provider>
                    </InitialSetupContext.Provider>
                </MessagingContext.Provider>
            </InlineErrorBoundary>
        </EnvironmentProvider>,
        root,
    );
}

/**
 * @param {Environment} environment
 */
async function getStrings(environment) {
    return environment.locale === 'en'
        ? enStrings
        : await fetch(`./locales/${environment.locale}/new-tab.json`)
              .then((x) => x.json())
              .catch((e) => {
                  console.error('Could not load locale', environment.locale, e);
                  return enStrings;
              });
}

/**
 * @param {Environment} environment
 * @param {Settings} settings
 */
function installGlobalSideEffects(environment, settings) {
    document.body.dataset.platformName = settings.platform.name;
    document.body.dataset.display = environment.display;
    document.body.dataset.animation = environment.urlParams.get('animation') || '';
}

/**
 *
 * @param {import('../types/new-tab.js').InitialSetupResponse['widgets']} widgets
 * @param {(message: string) => void} didCatch
 * @return {Promise<{[p: string]: any}|{}>}
 */
async function resolveEntryPoints(widgets, didCatch) {
    try {
        const loaders = widgets.map((widget) => {
            return (
                widgetEntryPoint(widget.id, didCatch)
                    // eslint-disable-next-line promise/prefer-await-to-then
                    .then((mod) => [widget.id, mod])
            );
        });
        const entryPoints = await Promise.all(loaders);
        return Object.fromEntries(entryPoints);
    } catch (e) {
        const error = new Error('Error loading widget entry points:' + e.message);
        didCatch(error.message);
        console.error(error);
        return {};
    }
}

/**
 * @param {Element} root
 * @param {Environment} environment
 * @param {Settings} settings
 * @param {Record<string, any>} strings
 */
function renderComponents(root, environment, settings, strings) {
    // eslint-disable-next-line no-labels,no-unused-labels
    $INTEGRATION: render(
        <EnvironmentProvider
            debugState={environment.debugState}
            injectName={environment.injectName}
            willThrow={environment.willThrow}
            locale={environment.locale}
        >
            <SettingsProvider settings={settings}>
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <Components />
                </TranslationProvider>
            </SettingsProvider>
        </EnvironmentProvider>,
        root,
    );
}
