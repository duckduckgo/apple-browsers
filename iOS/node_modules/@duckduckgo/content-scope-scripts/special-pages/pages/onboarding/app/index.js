import { OnboardingMessages } from './messages';
import { render, h } from 'preact';
import './styles/global.css'; // global styles
import { App, SkipLink } from './components/App.js';
import { App2 } from './components/App2';
import { GlobalProvider } from './global';
import { Components } from './Components';
import { EnvironmentProvider, UpdateEnvironment } from '../../../shared/components/EnvironmentProvider';
import { Environment } from '../../../shared/environment';
import { createSpecialPageMessaging } from '../../../shared/create-special-page-messaging';
import { Settings } from './settings';
import { callWithRetry } from '../../../shared/call-with-retry';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider';
import { SettingsProvider } from './components/SettingsProvider';
import enStrings from '../public/locales/en/onboarding.json';
import { stepDefinitions as stepDefinitionsV3 } from './components/v3/data';
import { mockTransport } from '../src/mock-transport.js';

const baseEnvironment = new Environment().withInjectName(document.documentElement.dataset.platform).withEnv(import.meta.env);

// share this in the app, it's an instance of `OnboardingMessages` where all your native comms should be
const messaging = createSpecialPageMessaging({
    injectName: baseEnvironment.injectName,
    env: baseEnvironment.env,
    pageName: 'onboarding',
    mockTransport: () => {
        // only in integration environments
        if (baseEnvironment.injectName !== 'integration') return null;
        let mock = null;

        mock = mockTransport();
        return mock;
    },
});

const onboarding = new OnboardingMessages(messaging, baseEnvironment.injectName);

async function init() {
    const result = await callWithRetry(() => onboarding.init());
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

    const strings =
        environment.locale === 'en'
            ? enStrings
            : await fetch(`./locales/${environment.locale}/onboarding.json`)
                  .then((x) => x.json())
                  .catch((e) => {
                      console.error('Could not load locale', environment.locale, e);
                      return enStrings;
                  });

    const settings = new Settings()
        .withPlatformName(baseEnvironment.injectName)
        .withPlatformName(init.platform?.name)
        .withPlatformName(baseEnvironment.urlParams.get('platform'))
        .withStepDefinitions(init.order === 'v3' ? stepDefinitionsV3 : null)
        .withStepDefinitions(init.stepDefinitions)
        .withNamedOrder(init.order)
        .withNamedOrder(environment.urlParams.get('order'))
        .withExcludedScreens(init.exclude)
        .withExcludedScreens(environment.urlParams.getAll('exclude'))
        .withFirst(environment.urlParams.get('page'));

    const AppComponent = settings.orderName === 'v3' ? App2 : App;

    const root = document.querySelector('#app');
    if (!root) throw new Error('could not render, root element missing');

    if (environment.display === 'app') {
        render(
            <EnvironmentProvider debugState={environment.debugState} injectName={environment.injectName} willThrow={environment.willThrow}>
                <UpdateEnvironment search={window.location.search} />
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <SettingsProvider platform={settings.platform}>
                        <GlobalProvider
                            messaging={onboarding}
                            order={settings.order}
                            stepDefinitions={settings.stepDefinitions}
                            firstPage={settings.first}
                        >
                            <AppComponent>{environment.env === 'development' && <SkipLink />}</AppComponent>
                        </GlobalProvider>
                    </SettingsProvider>
                </TranslationProvider>
            </EnvironmentProvider>,
            root,
        );
    }
    if (environment.display === 'components') {
        render(
            <EnvironmentProvider debugState={false} injectName={environment.injectName}>
                <TranslationProvider translationObject={strings} fallback={enStrings}>
                    <Components />
                </TranslationProvider>
            </EnvironmentProvider>,
            root,
        );
    }
}

init().catch((e) => {
    console.error(e);
    const msg = typeof e?.message === 'string' ? e.message : 'unknown init error';
    onboarding.reportInitException({ message: msg });
});
