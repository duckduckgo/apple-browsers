import { h, render } from 'preact';
import { EnvironmentProvider, UpdateEnvironment } from '../../../shared/components/EnvironmentProvider.js';

import { App } from './components/App.jsx';
import { Components } from './components/Components.jsx';

import enStrings from '../public/locales/en/example.json';
import { TranslationProvider } from '../../../shared/components/TranslationsProvider.js';
import { callWithRetry } from '../../../shared/call-with-retry.js';

import '../../../shared/styles/global.css'; // global styles

/**
 * @param {import("../src/index.js").ExamplePage} messaging
 * @param {import("../../../shared/environment").Environment} baseEnvironment
 * @return {Promise<void>}
 */
export async function init(messaging, baseEnvironment) {
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

    const strings =
        environment.locale === 'en'
            ? enStrings
            : await fetch(`./locales/${environment.locale}/example.json`)
                  .then((resp) => {
                      if (!resp.ok) {
                          throw new Error('did not give a result');
                      }
                      return resp.json();
                  })
                  .catch((e) => {
                      console.error('Could not load locale', environment.locale, e);
                      return enStrings;
                  });

    const root = document.querySelector('#app');
    if (!root) throw new Error('could not render, root element missing');

    if (environment.display === 'app') {
        render(
            <EnvironmentProvider debugState={environment.debugState} injectName={environment.injectName} willThrow={environment.willThrow}>
                <UpdateEnvironment search={window.location.search} />
                <TranslationProvider translationObject={strings} fallback={enStrings} textLength={environment.textLength}>
                    <App />
                </TranslationProvider>
            </EnvironmentProvider>,
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
