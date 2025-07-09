import { h, render } from 'preact';
import { EnvironmentProvider, UpdateEnvironment } from '../../../shared/components/EnvironmentProvider.js';

import { App } from './components/App.jsx';
import { Components } from './components/Components.jsx';

import enStrings from '../public/locales/en/special-error.json';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider.js';
import { MessagingProvider } from './providers/MessagingProvider.js';
import { SettingsProvider } from './providers/SettingsProvider.jsx';
import { SpecialErrorProvider } from './providers/SpecialErrorProvider.js';
import { callWithRetry } from '../../../shared/call-with-retry.js';

import { Settings } from './settings.js';
import { SpecialError } from './specialError.js';

import '../../../shared/styles/global.css'; // global styles
import './styles/variables.css';

/**
 * @param {import("../src/index.js").SpecialErrorPage} messaging
 * @param {import("../../../shared/environment").Environment} baseEnvironment
 * @return {Promise<void>}
 */
export async function init(messaging, baseEnvironment) {
    const result = await callWithRetry(() => messaging.initialSetup());
    if ('error' in result) {
        throw new Error(result.error);
    }

    const init = result.value;
    const missingProperties = ['errorData', 'platform'].filter((prop) => !init[prop]);
    if (missingProperties.length > 0) {
        throw new Error(`Missing setup data: ${missingProperties.join(', ')}`);
    }

    // update the 'env' in case it was changed by native sides
    const environment = baseEnvironment
        .withEnv(init.env)
        .withLocale(init.locale)
        .withLocale(baseEnvironment.urlParams.get('locale'))
        .withTextLength(baseEnvironment.urlParams.get('textLength'))
        .withDisplay(baseEnvironment.urlParams.get('display'));

    const strings =
        environment.locale === 'en'
            ? enStrings
            : (await getTranslationsFromStringOrLoadDynamically(init.localeStrings, environment.locale)) || enStrings;

    const settings = new Settings({})
        .withPlatformName(baseEnvironment.injectName)
        .withPlatformName(init.platform?.name)
        .withPlatformName(baseEnvironment.urlParams.get('platform'));

    document.body.dataset.platformName = settings.platform?.name;

    const specialError = new SpecialError({ errorData: init.errorData }).withSampleErrorId(baseEnvironment.urlParams.get('errorId'));

    const root = document.querySelector('#app');
    if (!root) throw new Error('could not render, root element missing');

    if (environment.display === 'app') {
        render(
            <EnvironmentProvider debugState={environment.debugState} injectName={environment.injectName} willThrow={environment.willThrow}>
                <UpdateEnvironment search={window.location.search} />
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <MessagingProvider messaging={messaging}>
                        <SettingsProvider settings={settings}>
                            <SpecialErrorProvider specialError={specialError}>
                                <App />
                            </SpecialErrorProvider>
                        </SettingsProvider>
                    </MessagingProvider>
                </TranslationProvider>
            </EnvironmentProvider>,
            root,
        );
    } else if (environment.display === 'components') {
        render(
            <EnvironmentProvider debugState={false} injectName={environment.injectName}>
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <SettingsProvider settings={settings}>
                        <SpecialErrorProvider specialError={specialError}>
                            <Components />
                        </SpecialErrorProvider>
                    </SettingsProvider>
                </TranslationProvider>
            </EnvironmentProvider>,
            root,
        );
    }
}

/**
 * @param {string|null|undefined} stringInput - optional string input. Might be a string of JSON
 * @param {string} locale
 * @return {Promise<Record<string, any> | null>}
 */
async function getTranslationsFromStringOrLoadDynamically(stringInput, locale) {
    /**
     * This is a special situation - the native side (iOS/macOS at the time) wanted to
     * use a single HTML file for the error pages. This created an issues since special pages
     * would like to load the translation files dynamically. The solution we came up with,
     * is to add the translation data as a string on the native side. This keeps all
     * the translations in the FE codebase.
     */
    if (stringInput) {
        try {
            return JSON.parse(stringInput);
        } catch (e) {
            console.warn('String could not be parsed. Falling back to fetch...');
        }
    }

    // If parsing failed or stringInput was null/undefined, proceed with fetch
    try {
        const response = await fetch(`./locales/${locale}/special-error.json`);
        if (!response.ok) {
            console.error('Network response was not ok');
            return null;
        }
        return await response.json();
    } catch (e) {
        console.error('Failed to fetch or parse JSON from the network:', e);
        return null;
    }
}
