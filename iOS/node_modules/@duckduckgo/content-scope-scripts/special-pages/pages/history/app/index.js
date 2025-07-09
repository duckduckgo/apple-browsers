import { h, render } from 'preact';
import { EnvironmentProvider, UpdateEnvironment } from '../../../shared/components/EnvironmentProvider.js';

import { App, AppLevelErrorBoundaryFallback } from './components/App.jsx';
import { Components } from './components/Components.jsx';

import enStrings from '../public/locales/en/history.json';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider.js';
import { callWithRetry } from '../../../shared/call-with-retry.js';

import { MessagingContext, SettingsContext } from './types.js';
import { HistoryService, paramsToQuery } from './history.service.js';
import { HistoryServiceProvider } from './global/Providers/HistoryServiceProvider.js';
import { Settings } from './Settings.js';
import { SelectionProvider } from './global/Providers/SelectionProvider.js';
import { QueryProvider } from './global/Providers/QueryProvider.js';
import { InlineErrorBoundary } from '../../../shared/components/InlineErrorBoundary.js';

/**
 * @param {Element} root
 * @param {import("../src/index.js").HistoryPage} messaging
 * @param {import("../../../shared/environment").Environment} baseEnvironment
 * @return {Promise<void>}
 */
export async function init(root, messaging, baseEnvironment) {
    const result = await callWithRetry(() => messaging.initialSetup());
    if ('error' in result) {
        throw new Error(result.error);
    }

    const init = result.value;

    // update the 'env' in case it was changed by native sides
    const environment = baseEnvironment
        .withEnv(init.env)
        .withLocale(init.locale)
        .withLocale(baseEnvironment.urlParams.get('locale'))
        .withTextLength(baseEnvironment.urlParams.get('textLength'))
        .withDisplay(baseEnvironment.urlParams.get('display'));

    // create app-specific settings
    const settings = new Settings({})
        .withPlatformName(baseEnvironment.injectName)
        .withPlatformName(init.platform?.name)
        .withPlatformName(baseEnvironment.urlParams.get('platform'))
        .withDebounce(baseEnvironment.urlParams.get('debounce'))
        .withUrlDebounce(baseEnvironment.urlParams.get('urlDebounce'));

    if (!window.__playwright_01) {
        console.log('initialSetup', init);
        console.log('environment', environment);
        console.log('settings', settings);
    }

    /**
     * @param {string} message
     */
    const didCatchInit = (message) => {
        messaging.reportInitException({ message });
    };

    // apply default styles
    applyDefaultStyles(init.customizer?.defaultStyles);

    const strings = await getStrings(environment);
    const service = new HistoryService(messaging);
    const query = paramsToQuery(environment.urlParams, 'initial');
    const initial = await fetchInitial(query, service, didCatchInit);

    if (environment.display === 'app') {
        render(
            <InlineErrorBoundary
                messaging={messaging}
                context={'History view application'}
                fallback={(message) => {
                    return <AppLevelErrorBoundaryFallback>{message}</AppLevelErrorBoundaryFallback>;
                }}
            >
                <EnvironmentProvider
                    debugState={environment.debugState}
                    injectName={environment.injectName}
                    willThrow={environment.willThrow}
                >
                    <UpdateEnvironment search={window.location.search} />
                    <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                        <MessagingContext.Provider value={messaging}>
                            <SettingsContext.Provider value={settings}>
                                <QueryProvider query={query.query}>
                                    <HistoryServiceProvider service={service} initial={initial}>
                                        <SelectionProvider>
                                            <App />
                                        </SelectionProvider>
                                    </HistoryServiceProvider>
                                </QueryProvider>
                            </SettingsContext.Provider>
                        </MessagingContext.Provider>
                    </TranslationProvider>
                </EnvironmentProvider>
            </InlineErrorBoundary>,
            root,
        );
    } else if (environment.display === 'components') {
        render(
            <EnvironmentProvider debugState={false} injectName={environment.injectName}>
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <Components />
                </TranslationProvider>
            </EnvironmentProvider>,
            root,
        );
    }
}

/**
 * This will apply default background colors as early as possible.
 *
 * @param {import("../types/history.ts").DefaultStyles | null | undefined} defaultStyles
 */
function applyDefaultStyles(defaultStyles) {
    if (defaultStyles?.lightBackgroundColor) {
        document.body.style.setProperty('--default-light-background-color', defaultStyles.lightBackgroundColor);
    }
    if (defaultStyles?.darkBackgroundColor) {
        document.body.style.setProperty('--default-dark-background-color', defaultStyles.darkBackgroundColor);
    }
}

/**
 * @param {import('../types/history.js').HistoryQuery} query
 * @param {HistoryService} service
 * @param {(message: string) => void} didCatch
 * @returns {Promise<import('./history.service.js').InitialServiceData>}
 */
async function fetchInitial(query, service, didCatch) {
    try {
        return await service.getInitial(query);
    } catch (e) {
        console.error(e);
        didCatch(e.message || String(e));
        return {
            ranges: {
                ranges: [{ id: 'all', count: 0 }],
            },
            query: {
                info: { query: { term: '' }, finished: true },
                results: [],
                lastQueryParams: null,
            },
        };
    }
}

/**
 * @param {import("../../../shared/environment").Environment} environment
 */
async function getStrings(environment) {
    return environment.locale === 'en'
        ? enStrings
        : await fetch(`./locales/${environment.locale}/history.json`)
              .then((x) => x.json())
              .catch((e) => {
                  console.error('Could not load locale', environment.locale, e);
                  return enStrings;
              });
}
