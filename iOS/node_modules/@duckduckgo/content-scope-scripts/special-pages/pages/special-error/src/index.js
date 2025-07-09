/**
 * Special Page that displays errors
 *
 * @module SSL Error Page
 */

import { createTypedMessages } from '@duckduckgo/messaging';
import { Environment } from '../../../shared/environment.js';
import { createSpecialPageMessaging } from '../../../shared/create-special-page-messaging.js';
import { mockTransport } from './mock-transport.js';
import { init } from '../app/index.js';

export class SpecialErrorPage {
    /**
     * @param {import("@duckduckgo/messaging").Messaging} messaging
     */
    constructor(messaging) {
        this.messaging = createTypedMessages(this, messaging);
    }

    /**
     * Sends an initial message to the native layer. This is the opportunity for the native layer
     * to provide the initial state of the application or any configuration, for example:
     *
     * ```json
     * {
     *   "env": "development",
     *   "locale": "en"
     * }
     * ```
     *
     * @returns {Promise<import('../types/special-error.ts').InitialSetupResponse>}
     */
    initialSetup() {
        return this.messaging.request('initialSetup');
    }

    /**
     * This will be sent if the application has loaded, but a client-side error
     * has occurred that cannot be recovered from
     * @param {{message: string}} params
     */
    reportPageException(params) {
        this.messaging.notify('reportPageException', params);
    }

    /**
     * This will be sent if the application fails to load.
     * @param {{message: string}} params
     */
    reportInitException(params) {
        this.messaging.notify('reportInitException', params);
    }

    /**
     * This will be sent when the user chooses to leave the current site
     */
    leaveSite() {
        this.messaging.notify('leaveSite');
    }

    /**
     * This will be sent when the user chooses to visit the current site despite warnings
     */
    visitSite() {
        this.messaging.notify('visitSite');
    }

    /**
     * This will be sent when the user clicks the Advanced Info button
     */
    advancedInfo() {
        this.messaging.notify('advancedInfo');
    }
}

const baseEnvironment = new Environment().withInjectName(document.documentElement.dataset.platform).withEnv(import.meta.env);

const messaging = createSpecialPageMessaging({
    injectName: baseEnvironment.injectName,
    env: baseEnvironment.env,
    pageName: /** @type {string} */ (import.meta.pageName),
    mockTransport: () => {
        // only in integration environments
        if (baseEnvironment.injectName !== 'integration') return null;
        let mock = null;
        // eslint-disable-next-line no-labels, no-unused-labels
        $INTEGRATION: mock = mockTransport();
        return mock;
    },
});

const specialErrorPage = new SpecialErrorPage(messaging);

init(specialErrorPage, baseEnvironment).catch((e) => {
    // messages.
    console.error(e);
    const msg = typeof e?.message === 'string' ? e.message : 'unknown init error';
    specialErrorPage.reportInitException({ message: msg });
});
