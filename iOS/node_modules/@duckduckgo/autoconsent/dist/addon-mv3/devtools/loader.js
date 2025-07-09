chrome.devtools.panels.create('Autoconsent', '/icons/cookie.png', '/devtools/panel.html');

if (chrome.devtools?.recorder) {
    class MyPlugin {
        stringify(recording) {
            const autoconsentSteps = recording.steps
                .filter((step) => ['click'].includes(step.type))
                .map(({ selectors }) => this.convertStep(selectors));
            return Promise.resolve(JSON.stringify(autoconsentSteps, undefined, 4));
        }
        stringifyStep(step) {
            return Promise.resolve(JSON.stringify(this.convertStep(step.selectors), undefined, 4));
        }
        convertStep(selectors) {
            return {
                any: selectors
                    .filter((s) => {
                        return this.isSupportedSelector(s);
                    })
                    .map((s) => {
                        if (s.length === 1) {
                            return {
                                waitForThenClick: s[0],
                            };
                        }
                        return {
                            waitForThenClick: s,
                        };
                    }),
            };
        }

        /**
         *
         * @param {string | string[]} selector
         * @returns
         */
        isSupportedSelector(selector) {
            const unsupportedPrefixes = ['aria/', 'pierce/', 'text/'];
            if (!Array.isArray(selector)) {
                return !unsupportedPrefixes.some((p) => selector.startsWith(p));
            }
            // Chained xpath selectors are not supported
            if (selector.length > 1 && selector.some((s) => s.startsWith('xpath/'))) {
                return false;
            }
            return selector.every((s) => this.isSupportedSelector(s));
        }
    }

    chrome.devtools.recorder.registerRecorderExtensionPlugin(
        new MyPlugin(),
        /* name= */ 'Autoconsent',
        /* mediaType= */ 'application/json',
    );
}
