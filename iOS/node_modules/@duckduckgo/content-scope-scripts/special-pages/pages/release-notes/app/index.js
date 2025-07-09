import { h, render, createContext } from 'preact';
import { useContext } from 'preact/hooks';
import { App } from './components/App';
import { Components } from './Components';
import { EnvironmentProvider } from '../../../shared/components/EnvironmentProvider';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider';
import { callWithRetry } from '../../../shared/call-with-retry.js';
import enStrings from '../public/locales/en/release-notes.json';

import '../../../shared/styles/global.css'; // global styles
import { Settings } from './settings';
import { SettingsProvider } from './settings.provider';

export const MessagingContext = createContext({
    messages: /** @type {import('../src/index.js').ReleaseNotesPage | null} */ (null),
});

export const useMessaging = () => useContext(MessagingContext);

/**
 * @import { Environment } from "../../../shared/environment";
 * @param {Environment} environment
 * @param {Settings} settings
 */
function installGlobalSideEffects(environment, settings) {
    document.body.dataset.platformName = settings.platform.name;
    document.body.dataset.display = environment.display;
}

export async function init(messages, baseEnvironment) {
    const result = await callWithRetry(() => messages.initialSetup());

    if ('error' in result) {
        throw new Error(result.error);
    }

    const init = result.value;

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
        .withPlatformName(baseEnvironment.urlParams.get('platform'));

    // install global side effects for platform-specific styles
    installGlobalSideEffects(environment, settings);

    const strings =
        environment.locale === 'en'
            ? enStrings
            : await fetch(`./locales/${environment.locale}/release-notes.json`)
                  .then((x) => x.json())
                  .catch((e) => {
                      console.error('Could not load locale', environment.locale, e);
                      return enStrings;
                  });

    const root = document.querySelector('#app');
    if (!root) throw new Error('could not render, root element missing');

    if (environment.display === 'app') {
        render(
            <EnvironmentProvider
                debugState={environment.debugState}
                injectName={environment.injectName}
                willThrow={environment.willThrow}
                env={environment.env}
            >
                <SettingsProvider settings={settings}>
                    <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                        <MessagingContext.Provider value={{ messages }}>
                            <App />
                        </MessagingContext.Provider>
                    </TranslationProvider>
                </SettingsProvider>
            </EnvironmentProvider>,
            root,
        );
    }
    if (environment.display === 'components') {
        render(
            <EnvironmentProvider debugState={environment.debugState} injectName={environment.injectName} willThrow={environment.willThrow}>
                <SettingsProvider settings={settings}>
                    <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                        <MessagingContext.Provider value={{ messages }}>
                            <Components />
                        </MessagingContext.Provider>
                    </TranslationProvider>
                </SettingsProvider>
            </EnvironmentProvider>,
            root,
        );
    }
}
