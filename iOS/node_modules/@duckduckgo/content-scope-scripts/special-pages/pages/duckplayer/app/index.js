import './index.css';
import { callWithRetry } from '../../../shared/call-with-retry.js';
import { h, render } from 'preact';
import { EnvironmentProvider, UpdateEnvironment, WillThrow } from '../../../shared/components/EnvironmentProvider.js';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider.js';
import { ErrorBoundary } from '../../../shared/components/ErrorBoundary.js';
import { EmbedSettings } from './embed-settings.js';
import enStrings from '../public/locales/en/duckplayer.json';
import { Settings } from './settings.js';
import { SettingsProvider } from './providers/SettingsProvider.jsx';
import { MessagingContext, TelemetryContext } from './types.js';
import { UserValuesProvider } from './providers/UserValuesProvider.jsx';
import { Fallback } from '../../../shared/components/Fallback/Fallback.jsx';
import { Components } from './components/Components.jsx';
import { MobileApp } from './components/MobileApp.jsx';
import { DesktopApp } from './components/DesktopApp.jsx';
import { YouTubeErrorProvider } from './providers/YouTubeErrorProvider';

/** @typedef {import('../types/duckplayer').YouTubeError} YouTubeError */

/**
 * @param {import("../src/index.js").DuckplayerPage} messaging
 * @param {import("../src/index.js").Telemetry} telemetry
 * @param {import("../../../shared/environment").Environment} baseEnvironment
 * @return {Promise<void>}
 */
export async function init(messaging, telemetry, baseEnvironment) {
    const result = await callWithRetry(() => messaging.initialSetup());
    if ('error' in result) {
        throw new Error(result.error);
    }

    const init = result.value;
    console.log('INITIAL DATA', init);

    // update the 'env' in case it was changed by native sides
    const environment = baseEnvironment
        .withEnv(init.env)
        .withLocale(init.locale)
        .withLocale(baseEnvironment.urlParams.get('locale'))
        .withTextLength(baseEnvironment.urlParams.get('textLength'))
        .withDisplay(baseEnvironment.urlParams.get('display'));

    console.log('environment:', environment);
    console.log('locale:', environment.locale);

    document.body.dataset.display = environment.display;

    const strings =
        environment.locale === 'en'
            ? enStrings
            : (await getTranslationsFromStringOrLoadDynamically(init.localeStrings, environment.locale)) || enStrings;

    const settings = new Settings({})
        .withPlatformName(baseEnvironment.injectName)
        .withPlatformName(init.platform?.name)
        .withPlatformName(baseEnvironment.urlParams.get('platform'))
        .withFeatureState('pip', init.settings.pip)
        .withFeatureState('autoplay', init.settings.autoplay)
        .withFeatureState('focusMode', init.settings.focusMode)
        .withFeatureState('customError', init.settings.customError)
        .withDisabledFocusMode(baseEnvironment.urlParams.get('focusMode'))
        .withCustomError(baseEnvironment.urlParams.get('customError'));

    const initialYouTubeError = /** @type {YouTubeError} */ (baseEnvironment.urlParams.get('youtubeError'));

    console.log(settings);

    const embed = createEmbedSettings(window.location.href, settings);

    const didCatch = (error) => {
        const message = error?.message || 'unknown';
        messaging.reportPageException({ message });
    };

    document.body.dataset.layout = settings.layout;

    const root = document.querySelector('body');
    if (!root) throw new Error('could not render, root element missing');

    if (environment.display === 'app') {
        render(
            <EnvironmentProvider debugState={environment.debugState} injectName={environment.injectName} willThrow={environment.willThrow}>
                <ErrorBoundary didCatch={didCatch} fallback={<Fallback showDetails={environment.env === 'development'} />}>
                    <UpdateEnvironment search={window.location.search} />
                    <TelemetryContext.Provider value={telemetry}>
                        <MessagingContext.Provider value={messaging}>
                            <SettingsProvider settings={settings}>
                                <YouTubeErrorProvider initial={initialYouTubeError} locale={environment.locale}>
                                    <UserValuesProvider initial={init.userValues}>
                                        {settings.layout === 'desktop' && (
                                            <TranslationProvider
                                                translationObject={enStrings}
                                                fallback={enStrings}
                                                textLength={environment.textLength}
                                            >
                                                <DesktopApp embed={embed} />
                                            </TranslationProvider>
                                        )}
                                        {settings.layout === 'mobile' && (
                                            <TranslationProvider
                                                translationObject={strings}
                                                fallback={enStrings}
                                                textLength={environment.textLength}
                                            >
                                                <MobileApp embed={embed} />
                                            </TranslationProvider>
                                        )}
                                        <WillThrow />
                                    </UserValuesProvider>
                                </YouTubeErrorProvider>
                            </SettingsProvider>
                        </MessagingContext.Provider>
                    </TelemetryContext.Provider>
                </ErrorBoundary>
            </EnvironmentProvider>,
            root,
        );
    } else if (environment.display === 'components') {
        render(
            <EnvironmentProvider debugState={false} injectName={environment.injectName}>
                <MessagingContext.Provider value={messaging}>
                    <TranslationProvider translationObject={enStrings} fallback={enStrings} textLength={environment.textLength}>
                        <Components />
                    </TranslationProvider>
                </MessagingContext.Provider>
            </EnvironmentProvider>,
            root,
        );
    }
}

/**
 * @param {string} href
 * @param {import("./settings.js").Settings} settings
 * @return {EmbedSettings|null}
 */
function createEmbedSettings(href, settings) {
    const embed = EmbedSettings.fromHref(href);
    if (!embed) return null;

    return embed.withAutoplay(settings.autoplay.state === 'enabled').withMuted(settings.platform.name === 'ios');
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
        const response = await fetch(`./locales/${locale}/duckplayer.json`);
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
